# Whoosh router + PG for cluster benchmarking
require "rack"
require "sequel"
require "json"
require_relative "../../lib/whoosh"

Whoosh::Performance.optimize!

DB_URL = ENV["DATABASE_URL"] || "postgres://localhost/whoosh_bench"

# Single shared connection pool (Sequel handles thread safety internally)
DB_PG = Sequel.connect(DB_URL, max_connections: 16)

router = Whoosh::Router.new
handler = {
  block: -> (env) {
    id = env["PATH_INFO"].split("/").last.to_i
    user = DB_PG[:users].where(id: id).first
    if user
      body = Whoosh::Serialization::Json.encode({
        id: user[:id], name: user[:name], email: user[:email], age: user[:age], role: user[:role]
      })
      [200, { "content-type" => "application/json" }, [body]]
    else
      [404, { "content-type" => "application/json" }, ['{"error":"not_found"}']]
    end
  },
  request_schema: nil, response_schema: nil, middleware: []
}
router.add("GET", "/users/:id", handler)
router.freeze!

app = -> (env) {
  match = router.match(env["REQUEST_METHOD"], env["PATH_INFO"])
  if match
    match[:handler][:block].call(env)
  else
    [404, { "content-type" => "application/json" }, ['{"error":"not_found"}']]
  end
}

run app
