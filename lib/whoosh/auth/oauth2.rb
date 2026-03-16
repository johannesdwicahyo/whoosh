# lib/whoosh/auth/oauth2.rb
# frozen_string_literal: true

module Whoosh
  module Auth
    class OAuth2
      def initialize(token_url: "/oauth/token", validator: nil)
        @token_url = token_url
        @validator = validator
      end

      def authenticate(request)
        auth_header = request.headers["Authorization"]
        raise Errors::UnauthorizedError, "Missing authorization header" unless auth_header

        token = auth_header.sub(/\ABearer\s+/i, "")
        raise Errors::UnauthorizedError, "Missing token" if token.empty?

        if @validator
          result = @validator.call(token)
          raise Errors::UnauthorizedError, "Invalid token" unless result
          result
        else
          { token: token }
        end
      end

      def token_url
        @token_url
      end
    end
  end
end
