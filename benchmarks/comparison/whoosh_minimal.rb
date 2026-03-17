# frozen_string_literal: true

# Whoosh with logging disabled — isolate framework overhead from log I/O
require "whoosh"

Whoosh::Performance.optimize!

APP_MINIMAL = Whoosh::App.new

# Silence the logger
APP_MINIMAL.instance_variable_get(:@logger).instance_variable_set(:@level, 99)

APP_MINIMAL.get "/health" do
  { status: "ok" }
end
