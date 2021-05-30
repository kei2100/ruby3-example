Fiber Scheduler
=

Fiber おさらい
==

Fiber は `Fiber.yield`/`Fiber#resume` を使うことで Fiber のブロックとその外側との
コンテキストスイッチを行うことができる。

```ruby
puts "1: Start program."

f = Fiber.new do
  puts "3: Entered fiber."
  Fiber.yield
  puts "5: Resumed fiber."
end

puts "2: Resume fiber first time."
f.resume

puts "4: Resume fiber second time."
f.resume

puts "6: Finished."
```

Scheduler
==

Fiber scheduler を使うと、Fiber 内で発生した kernel sleep や io など典型的なブロッキング処理が発生したタイミングで、
ユーザーが定義したハンドラにスイッチして任意の処理を行うことができる。
Fiber（軽量スレッド）による並行処理を柔軟に記述しやすくすることで、C10K のような問題を Ruby で問題なく処理できるようになることが期待される   

使い方としては、Scheduler インターフェースを実装したオブジェクトを `Fiber.set_scheduler(scheduler_object)` すると、現在実行中のスレッドにスケジューラを関連付けることができる。
スケジューラを関連付けると、次に Fiber がブロックする処理に入ったタイミングで、そのスケジューラへのスイッチが行われる。

例えば、以下は `kernel_sleep` を実装したスケジューラを `Fiber.set_scheduler(scheduler_object)` している。
次に Fiber が sleep すると、このスケジューラに処理がスイッチされる。

```ruby
class MyScheduler
  def kernel_sleep(duration = nil)
    p "b"
  end
end

Fiber.set_scheduler(MyScheduler.new)

Fiber.new do
  p "a"
  sleep(1)
  p "c"
end.resume

# a
# b
# c
```

スケジューラインターフェースの詳細は https://github.com/ruby/ruby/blob/master/doc/fiber.md を参照。
これらを正しく実装するのは少々大変なので、実際には Scheduler インターフェースを直接触るというよりは、 `async` などの gem を利用することが多そう。

```ruby
require 'async'
require 'net/http'
require 'uri'

Async do
  ["ruby", "rails", "async"].each do |topic|
    # async gem は、Net::HTTP をノンブロックとするために Fiber#scheduler を用いており、
    # 以下の HTTP リクエストは並行処理される
    Async do
      Net::HTTP.get(URI "https://www.google.com/search?q=#{topic}")
    end
  end
end
```
