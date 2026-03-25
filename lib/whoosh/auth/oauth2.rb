# frozen_string_literal: true

require "securerandom"

module Whoosh
  module Auth
    class OAuth2
      PROVIDERS = {
        google: {
          authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
          token_url: "https://oauth2.googleapis.com/token",
          userinfo_url: "https://www.googleapis.com/oauth2/v3/userinfo"
        },
        github: {
          authorize_url: "https://github.com/login/oauth/authorize",
          token_url: "https://github.com/login/oauth/access_token",
          userinfo_url: "https://api.github.com/user"
        },
        apple: {
          authorize_url: "https://appleid.apple.com/auth/authorize",
          token_url: "https://appleid.apple.com/auth/token",
          userinfo_url: nil
        }
      }.freeze

      attr_reader :provider

      def initialize(provider: :custom, client_id: nil, client_secret: nil,
                     authorize_url: nil, token_url: nil, userinfo_url: nil,
                     redirect_uri: nil, scopes: [], validator: nil)
        @provider = provider
        @client_id = client_id
        @client_secret = client_secret
        @authorize_url = authorize_url
        @token_url = token_url
        @userinfo_url = userinfo_url
        @redirect_uri = redirect_uri
        @scopes = scopes
        @validator = validator
        apply_provider_defaults if PROVIDERS[@provider]
      end

      def authorize_url(state: SecureRandom.hex(16))
        params = {
          client_id: @client_id, redirect_uri: @redirect_uri,
          response_type: "code", scope: @scopes.join(" "), state: state
        }
        "#{@authorize_url}?#{URI.encode_www_form(params)}"
      end

      def exchange_code(code)
        response = HTTP.post(@token_url, json: {
          client_id: @client_id, client_secret: @client_secret,
          code: code, redirect_uri: @redirect_uri, grant_type: "authorization_code"
        }, headers: { "Accept" => "application/json" })
        raise Errors::UnauthorizedError, "Token exchange failed: #{response.status}" unless response.ok?
        response.json
      end

      def userinfo(access_token)
        return nil unless @userinfo_url
        response = HTTP.get(@userinfo_url, headers: {
          "Authorization" => "Bearer #{access_token}", "Accept" => "application/json"
        })
        raise Errors::UnauthorizedError, "Userinfo failed" unless response.ok?
        response.json
      end

      def authenticate(request)
        auth_header = request.headers["Authorization"]
        raise Errors::UnauthorizedError, "Missing authorization" unless auth_header
        token = auth_header.sub(/\ABearer\s+/i, "")
        raise Errors::UnauthorizedError, "Missing token" if token.empty?

        if @validator
          result = @validator.call(token)
          raise Errors::UnauthorizedError, "Invalid token" unless result
          result
        elsif @userinfo_url
          userinfo(token)
        else
          { token: token }
        end
      end

      private

      def apply_provider_defaults
        defaults = PROVIDERS[@provider]
        @authorize_url ||= defaults[:authorize_url]
        @token_url ||= defaults[:token_url]
        @userinfo_url ||= defaults[:userinfo_url]
      end
    end
  end
end
