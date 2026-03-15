# lib/whoosh/streaming/sse.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module Streaming
    class SSE
      def self.headers
        {
          "content-type" => "text/event-stream",
          "cache-control" => "no-cache",
          "connection" => "keep-alive",
          "x-accel-buffering" => "no"
        }.freeze
      end

      def initialize(io)
        @io = io
        @closed = false
      end

      def <<(data)
        return if @closed
        formatted = data.is_a?(String) ? data : JSON.generate(data)
        write("data: #{formatted}\n\n")
        self
      end

      def event(name, data = nil)
        return if @closed
        write("event: #{name}\n")
        if data
          formatted = data.is_a?(String) ? data : JSON.generate(data)
          write("data: #{formatted}\n")
        end
        write("\n")
        self
      end

      def close
        return if @closed
        event("close")
        @closed = true
      end

      def closed?
        @closed
      end

      private

      def write(data)
        @io.write(data)
        @io.flush if @io.respond_to?(:flush)
      rescue IOError, Errno::EPIPE
        @closed = true
      end
    end
  end
end
