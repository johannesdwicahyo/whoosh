# frozen_string_literal: true

require_relative "../schemas/chat"

class ChatEndpoint < Whoosh::Endpoint
  post "/chat", request: ChatRequest, mcp: true

  def call(req)
    # In a real app, this would call an LLM
    { reply: "Echo: #{req.body[:message]}", model: req.body[:model] }
  end
end
