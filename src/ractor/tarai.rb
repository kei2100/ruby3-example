require "benchmark"

# 竹内関数
# https://ja.wikipedia.org/wiki/%E7%AB%B9%E5%86%85%E9%96%A2%E6%95%B0
def tarai(x, y, z)
  x <= y ? y : tarai(
    tarai(x - 1, y, z),
    tarai(y - 1, z, x),
    tarai(z - 1, x, y),
  )
end

Benchmark::bm do |x|
  x.report("sequential") { 4.times { tarai(14, 7, 0) } }

  x.report("parallel") {
    4.times.map {
      Ractor.new { tarai(14, 7, 0) }
    }.each(&:take)
  }
end
