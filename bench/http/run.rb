# HTTP benchmark: Whoosh, Grape and a plain Rails controller behind one Puma.
#   ruby bench/http/run.rb            # needs wrk (brew install wrk)
#   SECONDS=30 ruby bench/http/run.rb
require "json"
require "net/http"

DIR = __dir__
PORT = Integer(ENV.fetch("PORT", 9777))
SECONDS = Integer(ENV.fetch("SECONDS", 10))
ENV["BUNDLE_GEMFILE"] = File.join(DIR, "Gemfile")
system("bundle", "check", out: File::NULL) || system("bundle", "install") || abort("bundle install failed")
system("which", "wrk", out: File::NULL) || abort("wrk not found: brew install wrk")

# One Puma process, five threads, YJIT on.
puma = spawn({ "RAILS_ENV" => "production", "RUBYOPT" => "--yjit" },
             "bundle", "exec", "puma", "-t", "5:5", "-b", "tcp://127.0.0.1:#{PORT}", File.join(DIR, "config.ru"),
             out: File::NULL, err: File::NULL)
at_exit { Process.kill("TERM", puma) rescue nil }

def get(path, token: true)
  request = Net::HTTP::Get.new(path)
  request["Authorization"] = "Bearer t" if token
  Net::HTTP.start("127.0.0.1", PORT) { |http| http.request(request) }
end

up = 100.times.any? do
  get("/bare/noop")
rescue Errno::ECONNREFUSED
  sleep 0.2
  false
end
up or abort("Puma did not start; run `bundle exec puma bench/http/config.ru` in bench/http to see why")

GROUPS = {
  "Mounted in a Rails app" => { "whoosh" => "/whoosh", "grape" => "/grape", "rails" => "/rails" },
  "Straight on Puma, no Rails" => { "whoosh" => "/bare/whoosh", "grape" => "/bare/grape" }
}.freeze
FLOORS = { "Mounted in a Rails app" => "/noop", "Straight on Puma, no Rails" => "/bare/noop" }.freeze
ENDPOINTS = { "1 record" => "/items/7", "25 records" => "/items" }.freeze

# Refuse to compare unless every version does the same job: same JSON, and 401 without the token.
ENDPOINTS.each_value do |path|
  bodies = GROUPS.values.flat_map(&:values).map do |prefix|
    get(prefix + path, token: false).code == "401" or abort("#{prefix}#{path}: no auth check")
    response = get(prefix + path)
    response.code == "200" or abort("#{prefix}#{path}: #{response.code} #{response.body[0, 200]}")
    JSON.parse(response.body)
  end
  bodies.uniq.size == 1 or abort("responses differ for #{path}:\n#{bodies.map { |b| b.to_json[0, 200] }.join("\n")}")
end

def wrk(url, seconds)
  out = `wrk -t2 -c16 -d#{seconds}s --latency -H "Authorization: Bearer t" #{url}`
  out.include?("Non-2xx") and abort("errors under load:\n#{out}")
  [out[/Requests\/sec:\s+([\d.]+)/, 1].to_f, out[/^\s+50%\s+(\S+)/, 1], out[/^\s+99%\s+(\S+)/, 1]]
end

puts "#{RUBY_DESCRIPTION.split(" [").first}, Puma 1 process x 5 threads, wrk 16 connections, #{SECONDS}s each"
GROUPS.each do |group, frameworks|
  puts "\n#{group}"
  targets = ENDPOINTS.flat_map { |label, path| frameworks.map { |fw, prefix| ["#{fw}, #{label}", prefix + path] } }
  targets << ["empty response", FLOORS.fetch(group)]
  targets.each do |label, path|
    url = "http://127.0.0.1:#{PORT}#{path}"
    wrk(url, 3) # warm up, lets YJIT compile
    rps, p50, p99 = wrk(url, SECONDS)
    puts format("  %-20s %8.0f req/s  p50 %-8s p99 %s", label, rps, p50, p99)
  end
end
