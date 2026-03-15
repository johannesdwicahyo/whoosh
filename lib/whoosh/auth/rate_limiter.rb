# frozen_string_literal: true

module Whoosh
  module Auth
    class RateLimiter
      def initialize(default_limit: 60, default_period: 60, on_store_failure: :fail_open)
        @default_limit = default_limit
        @default_period = default_period
        @on_store_failure = on_store_failure
        @rules = {}
        @tiers = {}
        @store = {}
        @mutex = Mutex.new
      end

      def rule(path, limit:, period:)
        @rules[path] = { limit: limit, period: period }
      end

      def tier(name, limit: nil, period: nil, unlimited: false)
        @tiers[name] = { limit: limit, period: period, unlimited: unlimited }
      end

      def check!(key, path, tier: nil)
        limits = resolve_limits(path, tier)
        return if limits[:unlimited]

        bucket_key = "#{key}:#{path}"

        @mutex.synchronize do
          record = @store[bucket_key]
          now = Time.now.to_f

          if record.nil? || (now - record[:window_start]) >= limits[:period]
            @store[bucket_key] = { count: 1, window_start: now }
            return
          end

          if record[:count] >= limits[:limit]
            retry_after = (limits[:period] - (now - record[:window_start])).ceil
            raise Errors::RateLimitExceeded.new(retry_after: retry_after)
          end

          record[:count] += 1
        end
      rescue NoMethodError, TypeError
        if @on_store_failure == :fail_closed
          raise Errors::RateLimitExceeded.new("Rate limit store unavailable", retry_after: 60)
        end
      end

      def remaining(key, path, tier: nil)
        limits = resolve_limits(path, tier)
        return Float::INFINITY if limits[:unlimited]

        bucket_key = "#{key}:#{path}"

        @mutex.synchronize do
          record = @store[bucket_key]
          return limits[:limit] unless record

          now = Time.now.to_f
          return limits[:limit] if (now - record[:window_start]) >= limits[:period]

          [limits[:limit] - record[:count], 0].max
        end
      end

      private

      def resolve_limits(path, tier)
        if tier && @tiers[tier]
          tier_config = @tiers[tier]
          return { unlimited: true } if tier_config[:unlimited]
          return { limit: tier_config[:limit], period: tier_config[:period], unlimited: false }
        end

        if @rules[path]
          return { limit: @rules[path][:limit], period: @rules[path][:period], unlimited: false }
        end

        { limit: @default_limit, period: @default_period, unlimited: false }
      end
    end
  end
end
