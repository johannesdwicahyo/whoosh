require "sinatra/base"
require "sequel"
require "json"

DB_SIN_PG = Sequel.connect(ENV["DATABASE_URL"] || "postgres://localhost/whoosh_bench", max_connections: 16)

class SinatraPgApp < Sinatra::Base
  set :logging, false

  get "/users/:id" do
    content_type :json
    user = DB_SIN_PG[:users].where(id: params[:id].to_i).first
    if user
      JSON.generate({ id: user[:id], name: user[:name], email: user[:email], age: user[:age], role: user[:role] })
    else
      status 404
      JSON.generate({ error: "not_found" })
    end
  end
end

run SinatraPgApp
