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
        text = extract_text(chunk)
        return self if text.nil? || text.empty?
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

      # ruby_llm chunks expose #content (Message subclass). Older code paths
      # and plain-string yields are also supported.
      def extract_text(chunk)
        return chunk if chunk.is_a?(String)
        if chunk.respond_to?(:content)
          c = chunk.content
          return "" if c.nil?
          return c if c.is_a?(String)
          return c.text if c.respond_to?(:text)
          return c.to_s
        end
        return chunk.text if chunk.respond_to?(:text)
        chunk.to_s
      end

      def write(data)
        @io.write(data)
        @io.flush if @io.respond_to?(:flush)
      rescue IOError, Errno::EPIPE
        @closed = true
      end
    end
  end
end
