# frozen_string_literal: true

class ChatRequest < Whoosh::Schema
  field :message, String, required: true, desc: "The user message"
  field :model, String, default: "default", desc: "Model to use"
  field :temperature, Float, default: 0.7, min: 0.0, max: 2.0
end
