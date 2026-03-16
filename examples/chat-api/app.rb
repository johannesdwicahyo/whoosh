# frozen_string_literal: true

require "whoosh"
require "securerandom"

APP = Whoosh::App.new

# OpenAPI metadata
APP.openapi do
  title "Chat API"
  version "1.0.0"
  description "Example Whoosh chat API with auth, streaming, and MCP"
end

# Auth
APP.auth do
  api_key header: "X-Api-Key", keys: {
    "sk-demo-key" => { role: :standard },
    "sk-admin-key" => { role: :admin }
  }
end

APP.rate_limit do
  default limit: 60, period: 60
  rule "/chat", limit: 10, period: 60
end

APP.access_control do
  role :standard, models: ["default"]
  role :admin, models: ["default", "advanced"]
end

# Health check
APP.health_check

# Load class-based endpoints
APP.load_endpoints(File.join(__dir__, "endpoints"))

# Inline streaming endpoint
APP.post "/chat/stream", auth: :api_key do |req|
  stream_llm do |out|
    message = req.body ? req.body["message"] : "hello"
    words = "Streaming response to: #{message}".split(" ")
    words.each { |word| out << "#{word} " }
    out.finish
  end
end

# Inline SSE events endpoint
APP.get "/events" do
  stream :sse do |out|
    out.event("connected", { ts: Time.now.to_i })
    out.event("status", { users_online: 42 })
  end
end
