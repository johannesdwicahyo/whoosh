# spec/whoosh/streaming/sse_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Streaming::SSE do
  let(:io) { StringIO.new }
  let(:sse) { Whoosh::Streaming::SSE.new(io) }

  describe "#<<" do
    it "writes data as SSE format" do
      sse << { message: "hello" }
      io.rewind
      output = io.read
      expect(output).to include("data:")
      expect(output).to include("hello")
      expect(output).to end_with("\n\n")
    end

    it "writes raw string data" do
      sse << "plain text"
      io.rewind
      expect(io.read).to include("data: plain text")
    end
  end

  describe "#event" do
    it "writes a named event" do
      sse.event("status", { connected: true })
      io.rewind
      output = io.read
      expect(output).to include("event: status")
      expect(output).to include("data:")
      expect(output).to include("connected")
    end
  end

  describe "#close" do
    it "closes the stream" do
      sse.close
      io.rewind
      expect(io.read).to include("event: close")
    end
  end

  describe ".headers" do
    it "returns SSE content-type headers" do
      headers = Whoosh::Streaming::SSE.headers
      expect(headers["content-type"]).to eq("text/event-stream")
      expect(headers["cache-control"]).to eq("no-cache")
      expect(headers["connection"]).to eq("keep-alive")
    end
  end
end
