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

  describe "#stream" do
    before do
      fake_module = Module.new do
        def self.chat(*, **); end
      end
      stub_const("RubyLLM", fake_module)
      llm.instance_variable_set(:@ruby_llm, true)
      allow(llm).to receive(:ensure_ruby_llm!) # skip real require
    end

    it "raises DependencyError when ruby_llm is unavailable" do
      llm.instance_variable_set(:@ruby_llm, false)
      expect { llm.stream("hi") { |c| c } }.to raise_error(Whoosh::Errors::DependencyError, /ruby_llm/)
    end

    it "forwards each chunk from ruby_llm to the block" do
      chunk_class = Struct.new(:content)
      chunks = [chunk_class.new("Hel"), chunk_class.new("lo"), chunk_class.new("!")]

      fake_chat = double("RubyLLM::Chat")
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:ask) do |_msg, &block|
        chunks.each { |ch| block.call(ch) }
        chunk_class.new("Hello!")
      end
      allow(RubyLLM).to receive(:chat).with(model: Whoosh::AI::DEFAULT_MODEL).and_return(fake_chat)

      received = []
      llm.stream("say hi") { |c| received << c.content }

      expect(received).to eq(["Hel", "lo", "!"])
    end

    it "applies system instructions and a custom model" do
      fake_chat = double("RubyLLM::Chat")
      expect(fake_chat).to receive(:with_instructions).with("be terse").and_return(fake_chat)
      allow(fake_chat).to receive(:ask)
      expect(RubyLLM).to receive(:chat).with(model: "claude-haiku-4-5").and_return(fake_chat)

      llm.stream("hi", model: "claude-haiku-4-5", system: "be terse") { |_c| }
    end
  end
end

RSpec.describe Whoosh::Streaming::LlmStream do
  let(:io)     { StringIO.new }
  let(:stream) { described_class.new(io) }

  it "extracts text from ruby_llm Chunk-like objects via #content" do
    chunk = Struct.new(:content).new("hello")
    stream << chunk
    expect(io.string).to include(%("content":"hello"))
  end

  it "skips empty chunks (e.g. tool-call preludes with nil content)" do
    chunk = Struct.new(:content).new(nil)
    stream << chunk
    expect(io.string).to eq("")
  end

  it "accepts plain strings as chunks" do
    stream << "raw"
    expect(io.string).to include(%("content":"raw"))
  end

  it "unwraps Content-like objects (#content returns something with #text)" do
    content_obj = Struct.new(:text).new("inner")
    chunk = Struct.new(:content).new(content_obj)
    stream << chunk
    expect(io.string).to include(%("content":"inner"))
  end
end

RSpec.describe Whoosh::AI::LRUCache do
  it "returns nil for missing keys" do
    cache = described_class.new(2)
    expect(cache[:nope]).to be_nil
  end

  it "stores and retrieves values" do
    cache = described_class.new(2)
    cache[:a] = 1
    expect(cache[:a]).to eq(1)
  end

  it "evicts the oldest entry when over capacity" do
    cache = described_class.new(2)
    cache[:a] = 1
    cache[:b] = 2
    cache[:c] = 3
    expect(cache[:a]).to be_nil
    expect(cache[:b]).to eq(2)
    expect(cache[:c]).to eq(3)
    expect(cache.size).to eq(2)
  end

  it "promotes entries to most-recent on read" do
    cache = described_class.new(2)
    cache[:a] = 1
    cache[:b] = 2
    cache[:a] # touch :a — :b is now oldest
    cache[:c] = 3
    expect(cache[:a]).to eq(1)
    expect(cache[:b]).to be_nil
  end

  it "updates value in place without changing size" do
    cache = described_class.new(2)
    cache[:a] = 1
    cache[:a] = 2
    expect(cache[:a]).to eq(2)
    expect(cache.size).to eq(1)
  end
end

RSpec.describe "Whoosh::AI::LLM default model" do
  it "targets a current Claude model (not a retired id)" do
    expect(Whoosh::AI::DEFAULT_MODEL).to eq("claude-sonnet-4-6")
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
