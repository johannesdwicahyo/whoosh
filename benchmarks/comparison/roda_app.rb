# frozen_string_literal: true

require "roda"
require "json"

class RodaApp < Roda
  plugin :json

  route do |r|
    r.get "health" do
      { status: "ok" }
    end
  end
end
