# frozen_string_literal: true

module Whoosh
  module Auth
    class TokenTracker
      def initialize
        @usage = {}
        @callbacks = []
        @mutex = Mutex.new
      end

      def on_usage(&block)
        @callbacks << block
      end

      def record(key:, endpoint:, tokens:)
        total = tokens.values.sum
        @mutex.synchronize do
          @usage[key] ||= { total_tokens: 0, endpoints: {} }
          @usage[key][:total_tokens] += total
          @usage[key][:endpoints][endpoint] ||= 0
          @usage[key][:endpoints][endpoint] += total
        end
        @callbacks.each { |cb| cb.call(key, endpoint, tokens) }
      end

      def usage_for(key)
        @mutex.synchronize do
          data = @usage[key]
          return { total_tokens: 0, endpoints: {} } unless data
          { total_tokens: data[:total_tokens], endpoints: data[:endpoints].dup }
        end
      end

      def reset(key)
        @mutex.synchronize { @usage.delete(key) }
      end
    end
  end
end
