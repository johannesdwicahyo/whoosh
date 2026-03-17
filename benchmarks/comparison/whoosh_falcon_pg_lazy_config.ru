# Whoosh + Falcon + PG with LAZY connection pool (safe for fork)
# Connections created on first use in each worker, not at boot
require_relative "../../lib/whoosh"
require "pg"

Whoosh::Performance.optimize!

DB_URL = ENV["DATABASE_URL"] || "postgres://localhost/whoosh_bench"

class LazyPGPool
  def initialize(url, size: 16)
    @url = url
    @size = size
    @pool = nil
    @mutex = Mutex.new
  end

  def with
    ensure_pool!
    conn = @pool.pop
    yield conn
  ensure
    @pool << conn if conn && @pool
  end

  private

  def ensure_pool!
    return if @pool
    @mutex.synchronize do
      return if @pool
      @pool = Queue.new
      @size.times { @pool << PG.connect(@url) }
    end
  end
end

POOL = LazyPGPool.new(DB_URL, size: 16)

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
