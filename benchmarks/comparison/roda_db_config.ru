require "roda"
require "sequel"
require "json"

DB_RODA = Sequel.sqlite(File.join(__dir__, "bench.sqlite3"))

class RodaDbApp < Roda
  plugin :json

  route do |r|
    r.get "users", String do |id|
      user = DB_RODA[:users].where(id: id.to_i).first
      if user
        { id: user[:id], name: user[:name], email: user[:email], age: user[:age], role: user[:role] }
      else
        response.status = 404
        { error: "not_found" }
      end
    end
  end
end

run RodaDbApp.freeze.app
