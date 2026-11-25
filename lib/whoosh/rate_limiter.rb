module Whoosh
  # Fixed-window rate limiting, keyed by endpoint and client (the signed-in
  # user when there is one, otherwise the IP address).
  class RateLimiter
    Result = Struct.new(:limit, :remaining, :reset_in)

    def initialize(store, clock: -> { Time.now.to_i })
      @store = store
      @clock = clock
    end

    # Returns a Result, or raises TooManyRequests.
    def check!(scope, client, limit:, per:)
      now = @clock.call
      window = now / per
      reset_in = per - (now % per)
      count = @store.increment("rl:#{scope}:#{client}:#{window}", ttl: per + 1)
      remaining = [limit - count, 0].max

      if count > limit
        raise TooManyRequests.new(headers: {
          "retry-after" => reset_in.to_s,
          "x-ratelimit-limit" => limit.to_s,
          "x-ratelimit-remaining" => "0"
        })
      end

      Result.new(limit, remaining, reset_in)
    end
  end
end
