# frozen_string_literal: true

require "whoosh"

App = Whoosh::App.new

App.openapi do
  title "Test-whoosh-app API"
  version "0.1.0"
end

App.load_endpoints(File.join(__dir__, "endpoints"))
