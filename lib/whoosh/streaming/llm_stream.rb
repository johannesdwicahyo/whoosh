# lib/whoosh/streaming/llm_stream.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module Streaming
    class LlmStream
      def self.headers
        SSE.headers
      end

      def initialize(io)
        @io = io
        @closed = false
      end

      def <<(chunk)
        return if @closed
        text = chunk.respond_to?(:text) ? chunk.text : chunk.to_s
        payload = { choices: [{ delta: { content: text } }] }
        write("data: #{JSON.generate(payload)}\n\n")
        self
      end

      def finish
        return if @closed
        write("data: [DONE]\n\n")
        @closed = true
      end

      def error(type, message)
        return if @closed
        write("event: error\ndata: #{JSON.generate({ error: type, message: message })}\n\n")
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
