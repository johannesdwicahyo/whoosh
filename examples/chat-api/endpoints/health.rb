# frozen_string_literal: true

class HealthEndpoint < Whoosh::Endpoint
  get "/health"

  def call(req)
    { status: "ok", version: Whoosh::VERSION }
  end
end
