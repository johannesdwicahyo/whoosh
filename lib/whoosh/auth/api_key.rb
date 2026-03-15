# frozen_string_literal: true

module Whoosh
  module Auth
    class ApiKey
      def initialize(keys: {}, header: "X-Api-Key")
        @keys = keys.dup
        @header = header
        @mutex = Mutex.new
      end

      def authenticate(request)
        raw_value = request.headers[@header]
        raise Errors::UnauthorizedError, "Missing API key" unless raw_value
        key = raw_value.sub(/\ABearer\s+/i, "")
        metadata = @keys[key]
        raise Errors::UnauthorizedError, "Invalid API key" unless metadata
        { key: key, **metadata }
      end

      def register_key(key, **metadata)
        @mutex.synchronize { @keys[key] = metadata }
      end

      def revoke_key(key)
        @mutex.synchronize { @keys.delete(key) }
      end
    end
  end
end
