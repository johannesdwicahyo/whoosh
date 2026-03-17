require_relative "../../lib/whoosh"
require "sequel"

Whoosh::Performance.optimize!

DB_PG = Sequel.connect(ENV["DATABASE_URL"] || "postgres://localhost/whoosh_bench", max_connections: 16)

app = Whoosh::App.new
app.instance_variable_get(:@logger).instance_variable_set(:@level, 99)

app.get "/users/:id" do |req|
  user = DB_PG[:users].where(id: req.params[:id].to_i).first
  if user
    { id: user[:id], name: user[:name], email: user[:email], age: user[:age], role: user[:role] }
  else
    [404, { "content-type" => "application/json" }, ['{"error":"not_found"}']]
  end
end

run app.to_rack
