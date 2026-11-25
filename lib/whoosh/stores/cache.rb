module Whoosh
  module Stores
    # Adapts an ActiveSupport::Cache store (Rails.cache: Solid Cache, Redis,
    # Memcached) so limits and idempotency keys are shared across processes.
    #
    #   config.store = Whoosh::Stores::Cache.new(Rails.cache)
    class Cache
      def initialize(cache, namespace: "whoosh")
        @cache = cache
        @namespace = namespace
      end

      def increment(key, ttl:)
        k = namespaced(key)
        count = @cache.increment(k, 1, expires_in: ttl)
        return count if count

        # Some stores return nil for a missing key; seed it and retry.
        @cache.write(k, 1, expires_in: ttl, unless_exist: true, raw: true)
        @cache.increment(k, 1, expires_in: ttl) || 1
      end

      def read(key) = @cache.read(namespaced(key))

      def write(key, value, ttl:)
        @cache.write(namespaced(key), value, expires_in: ttl)
      end

      def write_unless_exists(key, value, ttl:)
        !!@cache.write(namespaced(key), value, expires_in: ttl, unless_exist: true)
      end

      def delete(key) = @cache.delete(namespaced(key))

      private

      def namespaced(key) = "#{@namespace}:#{key}"
    end
  end
end
