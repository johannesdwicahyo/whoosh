# frozen_string_literal: true

module Whoosh
  module Middleware
    class Cors
      DEFAULT_METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
      DEFAULT_HEADERS = "Content-Type, Authorization, X-API-Key, X-Request-ID"

      def initialize(app, origins: ["*"], methods: DEFAULT_METHODS, headers: DEFAULT_HEADERS, max_age: 86_400)
        @app = app
        @origins = origins
        @methods = methods
        @headers = headers
        @max_age = max_age
      end

      def call(env)
        origin = env["HTTP_ORIGIN"]

        if env["REQUEST_METHOD"] == "OPTIONS"
          return preflight_response(origin)
        end

        status, headers, body = @app.call(env)
        add_cors_headers(headers, origin)
        [status, headers, body]
      end

      private

      def preflight_response(origin)
        headers = {
          "access-control-allow-methods" => @methods,
          "access-control-allow-headers" => @headers,
          "access-control-max-age" => @max_age.to_s
        }
        add_cors_headers(headers, origin)
        [204, headers, []]
      end

      def add_cors_headers(headers, origin)
        allowed = allowed_origin(origin)
        return unless allowed

        headers["access-control-allow-origin"] = allowed
        headers["access-control-expose-headers"] = "X-Request-ID"
        headers["vary"] = "Origin"
      end

      def allowed_origin(origin)
        return nil unless origin

        if @origins.include?("*")
          "*"
        elsif @origins.include?(origin)
          origin
        end
      end
    end
  end
end
