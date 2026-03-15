# spec/whoosh/streaming/websocket_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Streaming::WebSocket do
  let(:io) { StringIO.new }
  let(:ws) { Whoosh::Streaming::WebSocket.new(io) }

  describe "#send" do
    it "writes text to the socket" do
      ws.send("hello")
      io.rewind
      expect(io.read).to include("hello")
    end

    it "serializes hashes to JSON" do
      ws.send({ msg: "hi" })
      io.rewind
      expect(JSON.parse(io.read.strip)).to eq({ "msg" => "hi" })
    end
  end

  describe "#on_message" do
    it "registers a message handler" do
      received = nil
      ws.on_message { |msg| received = msg }
      ws.trigger_message("test")
      expect(received).to eq("test")
    end
  end

  describe "#on_close" do
    it "registers a close handler" do
      closed = false
      ws.on_close { closed = true }
      ws.trigger_close
      expect(closed).to be true
    end
  end

  describe "#close" do
    it "closes the connection" do
      ws.close
      expect(ws.closed?).to be true
    end
  end
end
