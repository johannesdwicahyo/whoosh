# frozen_string_literal: true

require "sinatra/base"
require "json"

class SinatraApp < Sinatra::Base
  set :logging, false

  get "/health" do
    content_type :json
    JSON.generate({ status: "ok" })
  end
end
