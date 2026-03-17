require "sinatra/base"
require "sequel"
require "json"

DB_SINATRA = Sequel.sqlite(File.join(__dir__, "bench.sqlite3"))

class SinatraDbApp < Sinatra::Base
  set :logging, false

  get "/users/:id" do
    content_type :json
    user = DB_SINATRA[:users].where(id: params[:id].to_i).first
    if user
      JSON.generate({ id: user[:id], name: user[:name], email: user[:email], age: user[:age], role: user[:role] })
    else
      status 404
      JSON.generate({ error: "not_found" })
    end
  end
end

run SinatraDbApp
