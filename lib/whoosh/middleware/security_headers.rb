# frozen_string_literal: true

module Whoosh
  module Middleware
    class SecurityHeaders
      HEADERS = {
        "x-content-type-options" => "nosniff",
        "x-frame-options" => "DENY",
        "x-xss-protection" => "1; mode=block",
        "strict-transport-security" => "max-age=31536000; includeSubDomains",
        "x-download-options" => "noopen",
        "x-permitted-cross-domain-policies" => "none",
        "referrer-policy" => "strict-origin-when-cross-origin",
        "content-security-policy" => "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
      }.freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        headers = headers.dup if headers.frozen?
        HEADERS.each { |k, v| headers[k] ||= v }
        [status, headers, body]
      end
    end
  end
end
