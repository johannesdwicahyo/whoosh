require_relative "../../lib/whoosh"
require "sequel"

Whoosh::Performance.optimize!

# Disconnect before fork — Puma will reconnect in each worker
DB_URL = ENV["DATABASE_URL"] || "postgres://localhost/whoosh_bench"

app = Whoosh::App.new
app.instance_variable_get(:@logger).instance_variable_set(:@level, 99)

app.get "/users/:id" do |req|
  # Lazy connection per-thread (thread-safe via Sequel's connection pool)
  @_db ||= Sequel.connect(DB_URL, max_connections: 4)
  user = @_db[:users].where(id: req.params[:id].to_i).first
  if user
    { id: user[:id], name: user[:name], email: user[:email], age: user[:age], role: user[:role] }
  else
    [404, { "content-type" => "application/json" }, ['{"error":"not_found"}']]
  end
end

run app.to_rack
