# frozen_string_literal: true

module Whoosh
  module Cache
    autoload :MemoryStore, "whoosh/cache/memory_store"
    autoload :RedisStore,  "whoosh/cache/redis_store"

    # Auto-detect: REDIS_URL set → Redis, otherwise → Memory
    def self.build(config_data = {})
      cache_config = config_data["cache"] || {}
      default_ttl = cache_config["default_ttl"] || 300
      redis_url = ENV["REDIS_URL"] || cache_config["url"]

      if redis_url && cache_config["store"] != "memory"
        begin
          RedisStore.new(url: redis_url, default_ttl: default_ttl)
        rescue Errors::DependencyError
          # Redis gem not installed, fall back to memory
          MemoryStore.new(default_ttl: default_ttl)
        end
      else
        MemoryStore.new(default_ttl: default_ttl)
      end
    end
  end
end
