# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Streaming::WebSocket do
  describe ".websocket?" do
    it "detects WebSocket upgrade requests" do
      env = {
        "HTTP_UPGRADE" => "websocket",
        "HTTP_CONNECTION" => "Upgrade"
      }
      expect(Whoosh::Streaming::WebSocket.websocket?(env)).to be true
    end

    it "rejects non-WebSocket requests" do
      env = { "HTTP_UPGRADE" => nil }
      expect(Whoosh::Streaming::WebSocket.websocket?(env)).to be false
    end
  end

  describe "callbacks (test mode)" do
    let(:env) { { "HTTP_UPGRADE" => "websocket", "HTTP_CONNECTION" => "Upgrade" } }
    let(:ws) { Whoosh::Streaming::WebSocket.new(env) }

    it "triggers message handler" do
      received = nil
      ws.on_message { |msg| received = msg }
      ws.trigger_message("hello")
      expect(received).to eq("hello")
    end

    it "triggers close handler" do
      closed = false
      ws.on_close { closed = true }
      ws.trigger_close
      expect(closed).to be true
      expect(ws.closed?).to be true
    end
  end

  describe "#rack_response" do
    it "returns 400 for non-WebSocket requests" do
      env = {}
      ws = Whoosh::Streaming::WebSocket.new(env)
      status, _, _ = ws.rack_response
      expect(status).to eq(400)
    end

    it "returns 101 for WebSocket upgrade without hijack" do
      env = {
        "HTTP_UPGRADE" => "websocket",
        "HTTP_CONNECTION" => "Upgrade",
        "HTTP_SEC_WEBSOCKET_KEY" => "dGhlIHNhbXBsZSBub25jZQ=="
      }
      ws = Whoosh::Streaming::WebSocket.new(env)
      status, headers, _ = ws.rack_response
      expect(status).to eq(101)
      expect(headers["Upgrade"]).to eq("websocket")
      expect(headers["Sec-WebSocket-Accept"]).to be_a(String)
    end
  end
end
