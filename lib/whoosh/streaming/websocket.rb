# frozen_string_literal: true

require "json"

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
        upgrade = env["HTTP_UPGRADE"]
        upgrade && upgrade.downcase == "websocket"
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
      rescue
        # Already closed
      end

      def closed?
        @closed
      end

      # Returns a Rack response — auto-detects Faye (Puma) or Async (Falcon)
      def rack_response
        unless self.class.websocket?(@env)
          return [400, { "content-type" => "text/plain" }, ["Not a WebSocket request"]]
        end

        if async_websocket_available? && falcon_env?
          rack_response_async
        else
          rack_response_faye
        end
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

      private

      # Faye WebSocket — works with Puma (threads + EventMachine)
      def rack_response_faye
        require "faye/websocket"

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

      # Async WebSocket — works with Falcon (fibers + async)
      def rack_response_async
        require "async/websocket/adapters/rack"

        Async::WebSocket::Adapters::Rack.open(@env, protocols: ["ws"]) do |connection|
          @ws = AsyncWSWrapper.new(connection)
          @on_open&.call

          while (message = connection.read)
            @on_message&.call(message.to_str)
          end
        rescue EOFError, Protocol::WebSocket::ClosedError
          # Client disconnected
        ensure
          @closed = true
          @on_close&.call(1000, "")
          @ws = nil
        end
      end

      def falcon_env?
        # Falcon sets async.* keys in the env
        @env.key?("async.reactor") || @env.key?("protocol.http.request")
      end

      def async_websocket_available?
        require "async/websocket/adapters/rack"
        true
      rescue LoadError
        false
      end

      # Wrapper to give async-websocket the same #send interface
      class AsyncWSWrapper
        def initialize(connection)
          @connection = connection
        end

        def send(data)
          @connection.write(Protocol::WebSocket::TextMessage.generate(data))
          @connection.flush
        end

        def close(code = 1000, reason = "")
          @connection.close
        end
      end
    end
  end
end
