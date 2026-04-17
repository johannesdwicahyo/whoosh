# frozen_string_literal: true

module Whoosh
  module Streaming
    module Helpers
      def stream(type, &block)
        case type
        when :sse
          body = StreamBody.new do |out|
            sse = SSE.new(out)
            block.call(sse)
          end
          [200, SSE.headers, body]
        else
          raise ArgumentError, "Unknown stream type: #{type}"
        end
      end

      def stream_llm(&block)
        body = StreamBody.new do |out|
          llm_stream = LlmStream.new(out)
          block.call(llm_stream)
          llm_stream.finish
        end
        [200, LlmStream.headers, body]
      end
    end
  end
end
