# In-process benchmark of the full request pipeline (no HTTP server):
#   ruby --yjit -Ilib bench/pipeline.rb
require "whoosh"
require "stringio"

Item = Struct.new(:id, :name, :price, :created_at)
ITEMS = (1..25).map { |i| Item.new(i, "Item #{i}", BigDecimal("1000") * i, Time.now) }

class ItemSchema < Whoosh::Schema
  field :id, :integer
  field :name, :string
  field :price, :decimal
  field :created_at, :datetime
end

class BenchAPI < Whoosh::API
  version 1

  get "/items/:id" do
    authorize { |user| user }
    params { required :id, :integer }
    returns ItemSchema
    handle { |p| ITEMS[p[:id] - 1] }
  end

  get "/items" do
    authorize { |user| user }
    returns ItemSchema, many: true
    handle { ITEMS }
  end
end

Whoosh.configure do |c|
  c.authenticate = ->(req) { req.bearer_token == "t" ? :user : nil }
  c.rate_limit = [1_000_000_000, 60]
end

def env(path)
  { "REQUEST_METHOD" => "GET", "PATH_INFO" => path, "QUERY_STRING" => "", "REMOTE_ADDR" => "127.0.0.1",
    "rack.url_scheme" => "http", "rack.input" => StringIO.new, "HTTP_AUTHORIZATION" => "Bearer t" }
end

# BENCH_BUDGET="10,30" (µs for one record, for 25) makes the run fail when either is exceeded.
budgets = ENV["BENCH_BUDGET"]&.split(",")&.map(&:to_f)
over = false

[["single record", "/v1/items/7"], ["25 records", "/v1/items"]].each_with_index do |(label, path), i|
  5_000.times { BenchAPI.call(env(path)) }
  n = 50_000
  # Best of three: a noisy neighbour can only make a run slower, never faster.
  elapsed = 3.times.map do
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times { BenchAPI.call(env(path)) }
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  end.min
  micros = elapsed / n * 1_000_000
  line = format("%-14s %8.0f req/s  %6.1f µs/req", label, n / elapsed, micros)
  if budgets
    line += format("  budget %.0f µs", budgets[i])
    over ||= micros > budgets[i]
  end
  puts line
end
abort "over the speed budget" if over
