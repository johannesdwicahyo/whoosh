# frozen_string_literal: true

require "bundler/setup"
require "whoosh"
require "benchmark/ips"

router = Whoosh::Router.new
router.add("GET", "/health", -> { "ok" })
router.add("GET", "/users/:id", -> { "user" })
router.add("POST", "/users", -> { "create" })
router.add("GET", "/api/v1/items", -> { "items" })
router.add("GET", "/api/v1/items/:id", -> { "item" })
router.freeze!

puts "Router Benchmark (with static cache)"
puts "=" * 50

Benchmark.ips do |x|
  x.report("static: /health") { router.match("GET", "/health") }
  x.report("static: /api/v1/items") { router.match("GET", "/api/v1/items") }
  x.report("param: /users/42") { router.match("GET", "/users/42") }
  x.report("miss: /nonexistent") { router.match("GET", "/nonexistent") }

  x.compare!
end
