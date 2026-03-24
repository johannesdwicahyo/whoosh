# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Streaming::WebSocket do
  describe ".websocket?" do
    it "detects WebSocket upgrade requests" do
      env = Rack::MockRequest.env_for("/ws",
        "HTTP_UPGRADE" => "websocket",
        "HTTP_CONNECTION" => "Upgrade",
        "HTTP_SEC_WEBSOCKET_VERSION" => "13",
        "HTTP_SEC_WEBSOCKET_KEY" => "dGhlIHNhbXBsZSBub25jZQ=="
      )
      expect(Whoosh::Streaming::WebSocket.websocket?(env)).to be true
    end

    it "rejects non-WebSocket requests" do
      env = Rack::MockRequest.env_for("/test")
      expect(Whoosh::Streaming::WebSocket.websocket?(env)).to be_falsey
    end
  end

  describe "callbacks (test mode)" do
    let(:env) { Rack::MockRequest.env_for("/ws") }
    let(:ws) { Whoosh::Streaming::WebSocket.new(env) }

    it "triggers message handler" do
      received = nil
      ws.on_message { |msg| received = msg }
      ws.trigger_message("hello")
      expect(received).to eq("hello")
    end

    it "triggers open handler" do
      opened = false
      ws.on_open { opened = true }
      ws.trigger_open
      expect(opened).to be true
    end

    it "triggers close handler with code and reason" do
      close_code = nil
      ws.on_close { |code, reason| close_code = code }
      ws.trigger_close(1000, "normal")
      expect(close_code).to eq(1000)
      expect(ws.closed?).to be true
    end
  end

  describe "#rack_response" do
    it "returns 400 for non-WebSocket requests" do
      env = Rack::MockRequest.env_for("/test")
      ws = Whoosh::Streaming::WebSocket.new(env)
      status, _, _ = ws.rack_response
      expect(status).to eq(400)
    end
  end

  describe "#send" do
    it "does not crash when ws is nil (not connected)" do
      env = Rack::MockRequest.env_for("/ws")
      ws = Whoosh::Streaming::WebSocket.new(env)
      expect { ws.send("hello") }.not_to raise_error
    end

    it "does not send when closed" do
      env = Rack::MockRequest.env_for("/ws")
      ws = Whoosh::Streaming::WebSocket.new(env)
      ws.close
      expect { ws.send("hello") }.not_to raise_error
    end
  end
end
