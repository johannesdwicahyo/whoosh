# frozen_string_literal: true

require "whoosh"
require "securerandom"

APP = Whoosh::App.new

# Enable performance optimizations (Oj auto-detect + YJIT)
Whoosh::Performance.optimize!

# OpenAPI metadata
APP.openapi do
  title "Chat API"
  version "1.0.1"
  description "Example Whoosh chat API with auth, streaming, and MCP"
end

# Enable Swagger UI and ReDoc
APP.docs enabled: true, redoc: true

# Auth — API key + JWT
APP.auth do
  api_key header: "X-Api-Key", keys: {
    "sk-demo-key" => { role: :standard },
    "sk-admin-key" => { role: :admin }
  }
end

# Rate limiting with tiers
APP.rate_limit do
  default limit: 60, period: 60
  rule "/chat", limit: 10, period: 60
  tier :standard, limit: 100, period: 60
  tier :admin, unlimited: true
end

# Per-key model access control
APP.access_control do
  role :standard, models: ["default"]
  role :admin, models: ["default", "advanced"]
end

# Token usage tracking
APP.token_tracking do
  on_usage do |key, endpoint, tokens|
    # In production, send to billing system
    puts "Token usage: key=#{key} endpoint=#{endpoint} tokens=#{tokens}"
  end
end

# Error tracking
APP.on_event(:error) do |data|
  puts "Error: #{data[:error].message} at #{data[:path]}"
end

# Health check with probes
APP.health_check do
  probe(:api) { true }
end

# Load class-based endpoints (auto-registers MCP tools for mcp: true routes)
APP.load_endpoints(File.join(__dir__, "endpoints"))

# Inline streaming endpoint — protected by API key
APP.post "/chat/stream", auth: :api_key do |req|
  stream_llm do |out|
    message = req.body ? req.body["message"] : "hello"
    words = "Streaming response to: #{message}".split(" ")
    words.each { |word| out << "#{word} " }
    out.finish
  end
end

# SSE events endpoint
APP.get "/events" do
  stream :sse do |out|
    out.event("connected", { ts: Time.now.to_i })
    out.event("status", { users_online: 42 })
  end
end

# MCP group — all routes exposed as MCP tools
APP.group "/tools", mcp: true do
  post "/translate" do |req|
    text = req.body ? req.body["text"] : ""
    { result: "Translated: #{text}" }
  end
end
