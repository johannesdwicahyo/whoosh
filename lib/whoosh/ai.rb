# frozen_string_literal: true

module Whoosh
  module AI
    autoload :LLM,              "whoosh/ai/llm"
    autoload :StructuredOutput, "whoosh/ai/structured_output"

    # Build an AI client from config
    def self.build(config_data = {})
      ai_config = config_data["ai"] || {}
      LLM.new(
        provider: ai_config["provider"] || "auto",
        model: ai_config["model"],
        cache_enabled: ai_config["cache"] != false
      )
    end
  end
end
