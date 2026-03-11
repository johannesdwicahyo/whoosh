# frozen_string_literal: true

require "json"

module Whoosh
  module Middleware
    class RequestLimit
      def initialize(app, max_bytes: 1_048_576) # 1MB default
        @app = app
        @max_bytes = max_bytes
      end

      def call(env)
        content_length = env["CONTENT_LENGTH"]&.to_i || 0

        if content_length > @max_bytes
          return [
            413,
            { "content-type" => "application/json" },
            [JSON.generate({ error: "request_too_large", max_bytes: @max_bytes })]
          ]
        end

        @app.call(env)
      end
    end
  end
end
