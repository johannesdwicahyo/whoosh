# frozen_string_literal: true

require "whoosh"

Whoosh::Performance.optimize!

APP = Whoosh::App.new

APP.get "/health" do
  { status: "ok" }
end
