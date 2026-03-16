# frozen_string_literal: true

require "bundler/setup"
require "whoosh"
require "rack"
require "benchmark/ips"

Whoosh::Performance.optimize!

NULL_IO = File.open(File::NULL, "w")

class BenchUserSchema < Whoosh::Schema
  field :name, String, required: true
  field :email, String, required: true
  field :age, Integer, min: 0, max: 150
end

app = Whoosh::App.new
app.logger.instance_variable_set(:@output, NULL_IO)
app.post("/users", request: BenchUserSchema) { |req| { ok: true } }
rack_app = app.to_rack

body = '{"name":"Alice","email":"a@b.com","age":25}'
env = Rack::MockRequest.env_for("/users", method: "POST", input: body, "CONTENT_TYPE" => "application/json")

puts "Schema Validation Endpoint Benchmark"
puts "Engine: #{Whoosh::Serialization::Json.engine}"
puts "=" * 50

Benchmark.ips do |x|
  x.report("POST /users (schema validated)") do
    rack_app.call(env.dup)
  end

  x.compare!
end
