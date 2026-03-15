# spec/whoosh/streaming/llm_stream_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Streaming::LlmStream do
  let(:io) { StringIO.new }
  let(:stream) { Whoosh::Streaming::LlmStream.new(io) }

  describe "#<<" do
    it "writes chunks in OpenAI-compatible SSE format" do
      stream << "Hello"
      io.rewind
      output = io.read
      expect(output).to include("data:")
      parsed = JSON.parse(output.match(/data: (.+)/)[1])
      expect(parsed["choices"][0]["delta"]["content"]).to eq("Hello")
    end

    it "handles object chunks with .text method" do
      chunk = double("chunk", text: "world")
      stream << chunk
      io.rewind
      output = io.read
      parsed = JSON.parse(output.match(/data: (.+)/)[1])
      expect(parsed["choices"][0]["delta"]["content"]).to eq("world")
    end
  end

  describe "#finish" do
    it "sends [DONE] marker" do
      stream.finish
      io.rewind
      expect(io.read).to include("data: [DONE]")
    end
  end

  describe "#error" do
    it "sends error event" do
      stream.error("llm_error", "Connection failed")
      io.rewind
      output = io.read
      expect(output).to include("event: error")
      expect(output).to include("llm_error")
    end
  end

  describe ".headers" do
    it "returns SSE headers" do
      expect(Whoosh::Streaming::LlmStream.headers["content-type"]).to eq("text/event-stream")
    end
  end
end
