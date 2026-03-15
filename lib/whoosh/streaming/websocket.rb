# lib/whoosh/streaming/websocket.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module Streaming
    class WebSocket
      def initialize(io)
        @io = io
        @closed = false
        @on_message = nil
        @on_close = nil
      end

      def send(data)
        return if @closed
        formatted = data.is_a?(String) ? data : JSON.generate(data)
        @io.write(formatted + "\n")
        @io.flush if @io.respond_to?(:flush)
      rescue IOError, Errno::EPIPE
        @closed = true
      end

      def on_message(&block)
        @on_message = block
      end

      def on_close(&block)
        @on_close = block
      end

      def trigger_message(msg)
        @on_message&.call(msg)
      end

      def trigger_close
        @on_close&.call
        @closed = true
      end

      def close
        @closed = true
      end

      def closed?
        @closed
      end
    end
  end
end
