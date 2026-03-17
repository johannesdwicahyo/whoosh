# Whoosh + Falcon + PG with fiber-aware connection pool
# PG gem v1.5+ supports Ruby's fiber scheduler automatically
require_relative "../../lib/whoosh"
require "pg"

Whoosh::Performance.optimize!

DB_URL = ENV["DATABASE_URL"] || "postgres://localhost/whoosh_bench"

# Connection pool using PG directly (fiber-safe)
# Each fiber gets its own connection from the pool
class PGPool
  def initialize(url, size: 16)
    @url = url
    @connections = Queue.new
    size.times { @connections << PG.connect(url) }
  end

  def with
    conn = @connections.pop
    yield conn
  ensure
    @connections << conn if conn
  end
end

POOL = PGPool.new(DB_URL, size: 16)

app = Whoosh::App.new
app.instance_variable_get(:@logger).instance_variable_set(:@level, 99)

app.get "/users/:id" do |req|
  POOL.with do |conn|
    result = conn.exec_params("SELECT id, name, email, age, role FROM users WHERE id = $1", [req.params[:id].to_i])
    if result.ntuples > 0
      row = result[0]
      { id: row["id"].to_i, name: row["name"], email: row["email"], age: row["age"].to_i, role: row["role"] }
    else
      [404, { "content-type" => "application/json" }, ['{"error":"not_found"}']]
    end
  end
end

run app.to_rack
