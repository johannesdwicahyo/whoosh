# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::AI::LLM do
  let(:llm) { Whoosh::AI::LLM.new }

  describe "#available?" do
    it "returns a boolean" do
      expect([true, false]).to include(llm.available?)
    end
  end

  describe "caching" do
    it "can be created with cache enabled" do
      cached_llm = Whoosh::AI::LLM.new(cache_enabled: true)
      expect(cached_llm).to be_a(Whoosh::AI::LLM)
    end

    it "can be created with cache disabled" do
      uncached = Whoosh::AI::LLM.new(cache_enabled: false)
      expect(uncached).to be_a(Whoosh::AI::LLM)
    end
  end
end

RSpec.describe Whoosh::AI::StructuredOutput do
  describe ".prompt_for" do
    it "generates a prompt from schema" do
      schema = Class.new(Whoosh::Schema) do
        field :name, String, required: true, desc: "User name"
        field :age, Integer, min: 0
      end

      prompt = Whoosh::AI::StructuredOutput.prompt_for(schema)
      expect(prompt).to include("name: string")
      expect(prompt).to include("(required)")
      expect(prompt).to include("age: integer")
      expect(prompt).to include("[min: 0]")
    end
  end
end

RSpec.describe Whoosh::AI do
  describe ".build" do
    it "creates an LLM client" do
      llm = Whoosh::AI.build({})
      expect(llm).to be_a(Whoosh::AI::LLM)
    end

    it "passes config options" do
      llm = Whoosh::AI.build({ "ai" => { "model" => "claude-haiku" } })
      expect(llm.model).to eq("claude-haiku")
    end
  end
end
