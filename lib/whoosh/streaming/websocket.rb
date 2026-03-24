# frozen_string_literal: true

require "json"
require "faye/websocket"

module Whoosh
  module Streaming
    class WebSocket
      attr_reader :env

      def initialize(env)
        @env = env
        @ws = nil
        @closed = false
        @on_open = nil
        @on_message = nil
        @on_close = nil
      end

      # Check if the request is a WebSocket upgrade
      def self.websocket?(env)
        Faye::WebSocket.websocket?(env)
      end

      # Register callbacks
      def on_open(&block)
        @on_open = block
      end

      def on_message(&block)
        @on_message = block
      end

      def on_close(&block)
        @on_close = block
      end

      # Send data to the client
      def send(data)
        return if @closed || @ws.nil?
        formatted = data.is_a?(String) ? data : JSON.generate(data)
        @ws.send(formatted)
      end

      def close(code = nil, reason = nil)
        return if @closed
        @closed = true
        @ws&.close(code || 1000, reason || "")
      end

      def closed?
        @closed
      end

      # Returns a Rack response — hijacks the connection via faye-websocket
      def rack_response
        unless self.class.websocket?(@env)
          return [400, { "content-type" => "text/plain" }, ["Not a WebSocket request"]]
        end

        @ws = Faye::WebSocket.new(@env)

        @ws.on :open do |_event|
          @on_open&.call
        end

        @ws.on :message do |event|
          @on_message&.call(event.data)
        end

        @ws.on :close do |event|
          @closed = true
          @on_close&.call(event.code, event.reason)
          @ws = nil
        end

        @ws.rack_response
      end

      # For testing without real socket
      def trigger_message(msg)
        @on_message&.call(msg)
      end

      def trigger_close(code = 1000, reason = "")
        @on_close&.call(code, reason)
        @closed = true
      end

      def trigger_open
        @on_open&.call
      end
    end
  end
end
