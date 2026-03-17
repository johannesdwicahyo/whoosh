require "roda"
require "sequel"
require "json"

DB_RODA_PG = Sequel.connect(ENV["DATABASE_URL"] || "postgres://localhost/whoosh_bench", max_connections: 16)

class RodaPgApp < Roda
  plugin :json

  route do |r|
    r.get "users", String do |id|
      user = DB_RODA_PG[:users].where(id: id.to_i).first
      if user
        { id: user[:id], name: user[:name], email: user[:email], age: user[:age], role: user[:role] }
      else
        response.status = 404
        { error: "not_found" }
      end
    end
  end
end

run RodaPgApp.freeze.app
