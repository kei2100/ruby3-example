> https://docs.ruby-lang.org/en/3.0.0/doc/ractor_md.html

Ractor
=
summary
==
### Multiple Ractors in an interpreter process

* `Ractor.new { expr }` すると、Ractor が生成され、expr が並列に実行される
* インタプリタが実行されると *main Ractor* (= main Thread) が起動され、main Ractor の中で記述したプログラムが実行される
* main Ractor が終了すると、main Ractor の中で起動されたすべての Ractor は、Thread と同じように終了リクエストを受信する
* それぞれの Ractor は一つ以上の Thread を担当する
* 一つの Ractor 内の 各Thread は、GVL の影響を受けるため並列には動作しない（C レベルの明示的な GVL の解放なしには）
  * おさらい：CRuby における Thread は GVL を有しており、同時に実行されるネイティブスレッドは常に一つ。IO 待ちなどのブロックする操作を行う場合には、
    GVL を解放し、その間複数スレッドで動作するような実装になっている
* が、異なる Ractor 間では、複数のネイティブスレッドで動作することができる
* Ractor を作成するオーバーヘッドは Thread と同等

### Limited sharing between multiple ractors

* Thread と異なり、Ractor 間では共有できないものが多く存在する（それによりスレッドセーフ性を実現する）
* いくつかのオブジェクトを除き、ほとんどのオブジェクトは共有することができない
* *unshareable-objects* を参照しない Frozen されたオブジェクトは *immutable objects* となり、Ractor 間で共有することができる
  * i = 123: i is an immutable object.
  * s = "str".freeze: s is an immutable object.
  * a = [1, [2], 3].freeze: a is not an immutable object because a refers unshareable-object [2] (which is not frozen).
  * h = {c: Object}.freeze: h is an immutable object because h refers Symbol :c and shareable Object class object which is not frozen.
* Class/Module は共有することができる
* また以下のオブジェクトは特別に共有することができる
  * Ractor オブジェクト自体
  * (and more...)

### Two-types communication between Ractors

* Ractor 間はメッセージを交換し合うことで情報を同期する
* メッセージ交換のプロトコルは *push-type* と *pull type* がある

#### push-type communication

* `Ractor#send(obj)` と `Ractor.receive()` で Ractor 間のメッセージパッシングを行うことができる
* Ractor には無限の受信キューがあり、送信側は `Ractor#send(obj)` によりブロックすることはない
* 受信側は `Ractor.receive()` によりキューに届いたメッセージを受信する。キューが空の場合はブロックする  
* 受信側は `Ractor.receive_if{ filter_expr }` により、`filter_expr` に一致するメッセージのみ受信することができる

#### pull-type communication

* `Ractor.yield(obj)` と `Ractor#take()` を使う
* 送信側の Ractor が `Ractor.yield(obj)` する。受信側は送信側 Ractor に対し `Ractor#take()` することで `obj` を受け取ることができる
* `Ractor.yield(obj)` と `Ractor#take()` は、それぞれの Ractor 間でメッセージ交換が行われるまでブロックする
* 複数の Ractor が `Ractor#take()` で受信待ちしている場合、`Ractor.yield(obj)` によるメッセージは唯一つの Ractor に対し送信される
* `pul-type communication`  では、送信側が受信者の Ractor を知っている必要があり、受信側は送信者を知る必要がなかったのに対し、`pull-type communication` では逆となり、
  送信側は受信者 Ractor を知る必要がなく、受信側が送信者を知っている必要がる、というプロトコルになっている

#### messaging examples

```ruby
r = Ractor.new do
    msg = Ractor.receive # Receive from r's incoming queue
    msg # send back msg as block return value
end

r.send 'ok' # Send 'ok' to r's incoming port -> incoming queue
r.take      # Receive from r's outgoing port
```

Ractor 間のメッセージ交換は以下のような関係になる。

```
  +------+        +---+
  * main |------> * r *---+
  +-----+         +---+   |
      ^                   |
      +-------------------+
```

`Ractor.yield(obj)` の例は以下の通り。

```ruby
r = Ractor.new do
  Ractor.yield 'ok'
  p 'done'
end
r.take #=> 'ok'
```

### Communication between Ractors using shareable container objects

* Ractor 間のコミュニケーションは、これまで説明した push-type/pull-type のメッセージ交換により行うことが基本だが、
  共有可能なコンテナオブジェクトを介してコミュニケーションする方法もある
* Ractor::TVar gem (ko1/ractor-tvar) を使うと、そのような共有可能コンテナオブジェクトによるコミュニケーションが可能になる

### Copy & Move semantics to send messages

* `unshareable-objects` をメッセージ交換すると、そのオブジェクトは `copy` もしくは `move` される
* `copy` はディーブコピーされる。`move` はメンバーシップが移動される。送信者によりオブジェクトのメンバーシップが移動されると、送信者はそのオブジェクトにアクセスすることはできなくなる
* これらのメカニズムにより、ある時点において、一つのオブジェクトにはただ一つの Ractor のみがアクセスすることが保証される
* 上記含め、オブジェクトのメッセージ送信方法は以下の3種類が用意されている
  * `shareable-objects` への参照を送信する方法（高速）
  * `unshareable-objects` を `copy` で送信する方法（低速）
  * `unshareable-objects` を `move` で送信する方法
* `unshareable-objects` はデフォルトでは `copy` で送信されるが、`Ractor#send(obj, move: true/false)` と `Ractor.yield(obj, move: true/false)` で `move:` キーワードの値を指定することにより、
  `copy` ではなく `move` で送信することができる

### Thread-safety

* `Ractor` は、これまで記述したような仕組みにより、スレッドセーフな並行プログラム作成の手助けをするが、書き方によってはスレッドセーフでないプログラムも作成できてしまう
* Class/Module は複数 Ractor に共有されるので、複数の Ractor がそれらを変更するようなコードは注意する必要がある
* `Ractor` にはブロックされる操作があるので（waiting send, waiting yield and waiting take）、デッドロックやライブロックが発生しないように注意する必要がある

Creation and termination
==
### Ractor.new

```ruby
# Ractor.new with a block creates new Ractor
r = Ractor.new do
  # This block will be run in parallel with other ractors
end

# You can name a Ractor with `name:` argument.
r = Ractor.new name: 'test-name' do
end

# and Ractor#name returns its name.
r.name #=> 'test-name'
```

```ruby
# The self of the given block is Ractor object itself.
r = Ractor.new do
  p self.class #=> Ractor
  self.object_id
end
r.take == self.object_id #=> false
```

```ruby
# Passed arguments to Ractor.new() becomes block parameters for the given block
# ブロックパラメータはオブジェクトの参照を渡すのではなく、メッセージとして送信されることに注意すること

r = Ractor.new 'ok' do |msg|
  msg #=> 'ok'
end
r.take #=> 'ok'

# almost similar to the last example
r = Ractor.new do
  msg = Ractor.receive
  msg
end
r.send 'ok'
r.take #=> 'ok'
```

### Given block isolation

* `Ractor.new { expr }` で、expr は `Proc#isolate` により外部のスコープから分離される
* これにより、他の Ractor から `unshareable-objects` がアクセスされることを防止する
* `Ractor.new` のタイミングで `Proc#isolate` が呼び出される（Ruby ユーザーには今の所非公開）。
  与えられた Proc オブジェクト（`{ expr }` の箇所）が、外部の `unshareable-objects` を参照しているなどの理由で隔離できない場合、
  エラーが発生する。

```ruby
begin
  a = true
  r = Ractor.new do
    a #=> ArgumentError because this block accesses `a`.
  end
  r.take # see later
rescue ArgumentError
end
```

### An execution result of given block

```ruby
r = Ractor.new do
  'ok'
end
r.take #=> `ok`

# almost similar to the last example
r = Ractor.new do
  Ractor.yield 'ok'
end
r.take #=> 'ok'
```

Ractor で発生したエラーは、その Ractor のメッセージの受信者に伝播される

```ruby
r = Ractor.new do
  raise 'ok' # exception will be transferred to the receiver
end

begin
  r.take
rescue Ractor::RemoteError => e
  e.cause.class   #=> RuntimeError
  e.cause.message #=> 'ok'
  e.ractor        #=> r
end
```

Communication between Ractors
==
### Sending/Receiving ports

すべての Ractor は `incoming-port` と `outgoing-port` のメッセージキューを持つ
`incoming-port` は受信サイズが無制限で、`Ractor#send(obj)` でメッセージを送信する側はブロックされることはない

```ruby
r = Ractor.new do
  msg = Ractor.receive # Receive from r's incoming queue
  msg # send back msg as block return value
end
r.send 'ok' # Send 'ok' to r's incoming port -> incoming queue
r.take      # Receive from r's outgoing port
```

上記コードでの Ractor 間のメッセージ交換は以下のような関係になる。

```
  +------+        +---+
  * main |------> * r *---+
  +-----+         +---+   |
      ^                   |
      +-------------------+
```

`Ractor.new` に引数としてメッセージを渡すこともできるので、上記コードは以下のようにも書くことができる。

```ruby
# Actual argument 'ok' for `Ractor.new()` will be send to created Ractor.
r = Ractor.new 'ok' do |msg|
  # Values for formal parameters will be received from incoming queue.
  # Similar to: msg = Ractor.receive

  msg # Return value of the given block will be sent via outgoing port
end

# receive from the r's outgoing port.
r.take #=> `ok`
```

### Return value of a block for Ractor.new

すでに説明したように、`Ractor.new { expr }` の expr は `Ractor#take` で取得することができる。

```ruby
Ractor.new{ 42 }.take #=> 42
```

Ractor のブロックに返り値があるとき、すでにその Ractor は死んでいるので、通常であれば他の Ractor からはアクセスできないようなオブジェクトも返却することができる

```ruby
r = Ractor.new do
  a = "hello"
  binding
end

r.take.eval("p a") #=> "hello" (other communication path can not send a Binding object directly)
```

### Wait for multiple Ractors with Ractor.select

`Ractor.select` で複数の Ractor の `yield` を待つことができる

```ruby
# Wait for single Ractor:
r1 = Ractor.new{'r1'}

r, obj = Ractor.select(r1)
r == r1 and obj == 'r1' #=> true


# Wait for two ractors:
r1 = Ractor.new{'r1'}
r2 = Ractor.new{'r2'}
rs = [r1, r2]
as = []

# Wait for r1 or r2's Ractor.yield
r, obj = Ractor.select(*rs)
rs.delete(r)
as << obj

# Second try (rs only contain not-closed ractors)
r, obj = Ractor.select(*rs)
rs.delete(r)
as << obj
as.sort == ['r1', 'r2'] #=> true 
```

* TODO: Current Ractor.select() has the same issue of select(2), so this interface should be refined.
* TODO: select syntax of go-language uses round-robin technique to make fair scheduling. Now Ractor.select() doesn't use it.

### Closing Ractor's ports

* `Ractor#close_incoming/outgoing` でそれぞれのメッセージキューをクローズすることができる
* incoming-port がクローズされた Ractor に `r.send(obj)` することはできず、例外が raise される
* incoming-port がクローズされた Ractor が `Ractor.receive` した場合、キューが空であれば例外が raise される
* outgoing-port がクローズされた Ractor が `Ractor.yield` すると、例外が raise される
* outgoing-port がクローズされた Ractor に対し `r.take` すると、例外が raise される。ブロック中の場合も例外が raise される
* 終了した Ractor の port は自動的にクローズされる

```ruby
# try to take from closed Ractor
r = Ractor.new do
    'finish'
end
r.take # success (will return 'finish')
begin
  o = r.take # try to take from closed Ractor
rescue Ractor::ClosedError
  'ok'
else
  "ng: #{o}"
end

# try to send to closed (terminated) Ractor
r = Ractor.new do
end

r.take # wait terminate

begin
  r.send(1)
rescue Ractor::ClosedError
  'ok'
else
  'ng'
end
```

### Send a message by copying

* unshareble-object を `r.send(obj)` あるいは `Ractor.yield(obj)` すると、値がディープコピーが送信される
* いくつかの object は値のコピーをサポートしておらず例外を raise する

```ruby
obj = 'str'.dup
r = Ractor.new obj do |msg|
  # return received msg's object_id
  msg.object_id
end

obj.object_id == r.take #=> false

# Thread object is not supported to copy the value
obj = Thread.new{}
begin
  Ractor.new obj do |msg|
    msg
  end
rescue TypeError => e
  e.message #=> #<TypeError: allocator undefined for Thread>
else
  'ng' # unreachable here
end
```

### Send a message by moving

* `Ractor#send(obj, move: true)` あるいは `Ractor.yield(obj, move: true)` すると、ディープコピーではなく、
  `obj` のメンバーシップを送信先の Ractor へ move して渡すことができる
* 送信元の Ractor からすでに move された `obj` を参照しようとするとエラーになる

```ruby
# move with Ractor#send
r = Ractor.new do
  obj = Ractor.receive
  obj << ' world'
end

str = 'hello'
r.send str, move: true
modified = r.take #=> 'hello world'

# str is moved, and accessing str from this Ractor is prohibited

begin
  # Error because it touches moved str.
  str << ' exception' # raise Ractor::MovedError
rescue Ractor::MovedError
  modified #=> 'hello world'
else
  raise 'unreachable'
end

# move with Ractor.yield
r = Ractor.new do
  obj = 'hello'
  Ractor.yield obj, move: true
  obj << 'world'  # raise Ractor::MovedError
end

str = r.take
begin
  r.take
rescue Ractor::RemoteError
  p str #=> "hello"
end
```

* いくつかのオブジェクトは move をサポートしない

```ruby
r = Ractor.new do
  Ractor.receive
end

r.send(Thread.new{}, move: true) #=> allocator undefined for Thread (TypeError)
```

### Shareable objects

以下のオブジェクトは shareable-object である

* Immutable objects
* Small integers, some symbols, true, false, nil (a.k.a. SPECIAL_CONST_P() objects in internal)
* Frozen native objects
  * Numeric objects: Float, Complex, Rational, big integers (T_BIGNUM in internal)
  * All Symbols.
* Frozen String and Regexp objects (their instance variables should refer only sharble objects)
* Class, Module objects (T_CLASS, T_MODULE and T_ICLASS in internal)
* Ractor and other special objects which care about synchronization.

shareable-object の作成をサポートするめに、`Ractor.make_shareable(obj)` メソッドが提供されている

* `Ractor.make_shareble(obj, copy: false)` すると、obj とその中身を再帰的に freeze して move 可能な shareable-object を作成しようとする。`copy:` キーワードのデフォルトは false
* `Ractor.make_sharable(obj, copy: true)` すると、obj をディープコピーしたオブジェクトを shareable-object にしようとする

Language changes to isolate unshareable objects between Ractors
==

### Global Variables

* グローバル変数には main Ractor のみアクセス可能
* ただし、$stdin/$stdout/$stderr については ractor-local になる

### Instance variables of shareable-objects

* main Ractor のみが shareable-objects のインスタンス変数にアクセス可能
* クラス/モジュールオブジェクトのインスタンス変数も禁止されていることに注意

```ruby
class C
  @iv = 'str'
end

r = Ractor.new do
  class C
    p @iv
  end
end


begin
  r.take
rescue => e
  e.class #=> Ractor::IsolationError
end

shared = Ractor.new{}
shared.instance_variable_set(:@iv, 'str')

r = Ractor.new shared do |shared|
  p shared.instance_variable_get(:@iv)
end

begin
  r.take
rescue Ractor::RemoteError => e
  e.cause.message #=> can not access instance variables of shareable objects from non-main Ractors (Ractor::IsolationError)
end
```

### Class variables

* main Ractor のみがクラス変数にアクセス可能

```ruby
class C
  @@cv = 'str'
end

r = Ractor.new do
  class C
    p @@cv
  end
end

begin
  r.take
rescue => e
  e.class #=> Ractor::IsolationError
end
```

### Constants

* unshareable-objects を参照する定数には main Ractor からしかアクセスできない
* また main Ractor のみが unshareble-objects を参照する定数を定義できる

```ruby
class C
  CONST = 'str'
end
r = Ractor.new do
  C::CONST
end
begin
  r.take
rescue => e
  e.class #=> Ractor::IsolationError
end

class C
end
r = Ractor.new do
  C::CONST = 'str'
end
begin
  r.take
rescue => e
  e.class #=> Ractor::IsolationError
end
```
