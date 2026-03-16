# lib/whoosh/cache.rb
# frozen_string_literal: true

module Whoosh
  module Cache
    autoload :MemoryStore, "whoosh/cache/memory_store"
    autoload :RedisStore,  "whoosh/cache/redis_store"

    def self.build(config_data = {})
      cache_config = config_data["cache"] || {}
      store = cache_config["store"] || "memory"
      default_ttl = cache_config["default_ttl"] || 300

      case store
      when "memory"
        MemoryStore.new(default_ttl: default_ttl)
      when "redis"
        url = cache_config["url"] || "redis://localhost:6379"
        pool_size = cache_config["pool_size"] || 5
        RedisStore.new(url: url, default_ttl: default_ttl, pool_size: pool_size)
      else
        raise ArgumentError, "Unknown cache store: #{store}"
      end
    end
  end
end
