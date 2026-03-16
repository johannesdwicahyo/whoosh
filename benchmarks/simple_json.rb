# frozen_string_literal: true

require "bundler/setup"
require "whoosh"
require "rack"
require "benchmark/ips"

Whoosh::Performance.optimize!

app = Whoosh::App.new
app.logger.instance_variable_set(:@output, File.open(File::NULL, "w"))
app.get("/health") { { status: "ok" } }
rack_app = app.to_rack

env = Rack::MockRequest.env_for("/health")

puts "Simple JSON Endpoint Benchmark"
puts "Engine: #{Whoosh::Serialization::Json.engine}"
puts "YJIT: #{Whoosh::Performance.yjit_enabled?}"
puts "=" * 50

Benchmark.ips do |x|
  x.report("GET /health (full stack)") do
    rack_app.call(env.dup)
  end

  x.compare!
end
