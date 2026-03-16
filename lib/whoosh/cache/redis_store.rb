# lib/whoosh/cache/redis_store.rb
# frozen_string_literal: true

module Whoosh
  module Cache
    class RedisStore
      @redis_available = nil

      def self.available?
        if @redis_available.nil?
          @redis_available = begin
            require "redis"
            true
          rescue LoadError
            false
          end
        end
        @redis_available
      end

      def initialize(url:, default_ttl: 300, pool_size: 5)
        unless self.class.available?
          raise Errors::DependencyError, "Cache Redis store requires the 'redis' gem"
        end
        @redis = Redis.new(url: url)
        @default_ttl = default_ttl
      end

      def get(key)
        raw = @redis.get(key)
        return nil unless raw
        Serialization::Json.decode(raw)
      rescue => e
        nil
      end

      def set(key, value, ttl: nil)
        ttl ||= @default_ttl
        @redis.set(key, Serialization::Json.encode(value), ex: ttl)
        true
      rescue => e
        false
      end

      def fetch(key, ttl: nil)
        existing = get(key)
        return existing unless existing.nil?
        value = yield
        set(key, value, ttl: ttl)
        Serialization::Json.decode(Serialization::Json.encode(value))
      end

      def delete(key)
        @redis.del(key) > 0
      rescue => e
        false
      end

      def clear
        @redis.flushdb
        true
      rescue => e
        false
      end

      def close
        @redis.close
      rescue => e
      end
    end
  end
end
