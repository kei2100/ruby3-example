RBS
=

* Ruby プログラムの型を記述するための言語
* typeprof などの型検査ツールは、RBS を使うことでコードを精度よく検査することができる
* steep gem は、RBS の定義にしたがってコードを検査し型に一致しない呼び出しを検出する

RBS ファイル外観
==

```ruby
module ChatApp
  VERSION: String

  class User
    attr_reader login: String
    attr_reader email: String

    def initialize: (login: String, email: String) -> void
  end

  class Bot
    attr_reader name: String
    attr_reader email: String
    attr_reader owner: User

    def initialize: (name: String, owner: User) -> void
  end

  class Message
    attr_reader id: String
    attr_reader string: String
    attr_reader from: User | Bot                     # `|` means union types: `#from` can be `User` or `Bot`
    attr_reader reply_to: Message?                   # `?` means optional type: `#reply_to` can be `nil`

    def initialize: (from: User | Bot, string: String) -> void

    def reply: (from: User | Bot, string: String) -> Message
  end

  class Channel
    attr_reader name: String
    attr_reader messages: Array[Message]
    attr_reader users: Array[User]
    attr_reader bots: Array[Bot]

    def initialize: (name: String) -> void

    def each_member: () { (User | Bot) -> void } -> void  # `{` and `}` means block.
                   | () -> Enumerator[User | Bot, void]   # Method can be overloaded.
  end
end
```

TypeProf
=

typeprof を使うことで、Ruby コードから推論して RBS ファイルを生成することができる。
精度はまだまだこれからとのこと。

```ruby
# typeprof_example.rb
 
class MyClass
  attr_accessor :my_attr

  def strip_my_attr
    my_attr.strip
  end
end

mc = MyClass.new
mc.my_attr = "  foo  "
puts mc.strip_my_attr
```

```bash
$ typeprof typeprof_example.rb > typeprof_example.rbs
```

```ruby
# typeprof_example.rbs

# Classes
class MyClass
  attr_accessor my_attr: String
  def strip_my_attr: -> String
end
```
