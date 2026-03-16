# lib/whoosh/cache/memory_store.rb
# frozen_string_literal: true

module Whoosh
  module Cache
    class MemoryStore
      def initialize(default_ttl: 300)
        @store = {}
        @default_ttl = default_ttl
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize do
          entry = @store[key]
          return nil unless entry
          if entry[:expires_at] && Time.now.to_f > entry[:expires_at]
            @store.delete(key)
            return nil
          end
          entry[:value]
        end
      end

      def set(key, value, ttl: nil)
        ttl ||= @default_ttl
        serialized = Serialization::Json.decode(Serialization::Json.encode(value))
        @mutex.synchronize do
          @store[key] = { value: serialized, expires_at: Time.now.to_f + ttl }
        end
        true
      end

      def fetch(key, ttl: nil)
        existing = get(key)
        return existing unless existing.nil?
        value = yield
        set(key, value, ttl: ttl)
        Serialization::Json.decode(Serialization::Json.encode(value))
      end

      def delete(key)
        @mutex.synchronize { @store.delete(key) }
        true
      end

      def clear
        @mutex.synchronize { @store.clear }
        true
      end

      def close
        # No-op
      end
    end
  end
end
