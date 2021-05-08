> https://docs.ruby-lang.org/en/3.0.0/doc/ractor_md.html

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
