# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

module Whoosh
  module Auth
    class Jwt
      def initialize(secret:, algorithm: :hs256, expiry: 3600)
        @secret = secret
        @algorithm = algorithm
        @expiry = expiry
      end

      def generate(sub:, **claims)
        header = { alg: "HS256", typ: "JWT" }
        now = Time.now.to_i
        payload = { sub: sub, iat: now, exp: now + @expiry }.merge(claims)

        header_b64 = base64url_encode(JSON.generate(header))
        payload_b64 = base64url_encode(JSON.generate(payload))
        signature = sign("#{header_b64}.#{payload_b64}")

        "#{header_b64}.#{payload_b64}.#{signature}"
      end

      def authenticate(request)
        auth_header = request.headers["Authorization"]
        raise Errors::UnauthorizedError, "Missing authorization header" unless auth_header
        token = auth_header.sub(/\ABearer\s+/i, "")
        decode(token)
      end

      private

      def decode(token)
        parts = token.split(".")
        raise Errors::UnauthorizedError, "Invalid token format" unless parts.length == 3

        header_b64, payload_b64, signature = parts

        expected_sig = sign("#{header_b64}.#{payload_b64}")
        unless secure_compare(signature, expected_sig)
          raise Errors::UnauthorizedError, "Invalid token signature"
        end

        payload = JSON.parse(base64url_decode(payload_b64))

        if payload["exp"] && payload["exp"] < Time.now.to_i
          raise Errors::UnauthorizedError, "Token expired"
        end

        payload.transform_keys(&:to_sym)
      rescue JSON::ParserError
        raise Errors::UnauthorizedError, "Invalid token payload"
      end

      def sign(data)
        digest = OpenSSL::Digest.new("SHA256")
        signature_bytes = OpenSSL::HMAC.digest(digest, @secret, data)
        Base64.urlsafe_encode64(signature_bytes, padding: false)
      end

      def base64url_encode(data)
        Base64.urlsafe_encode64(data, padding: false)
      end

      def base64url_decode(str)
        Base64.urlsafe_decode64(str)
      end

      def secure_compare(a, b)
        # Use HMAC-based comparison to prevent length oracle attacks.
        # Comparing raw strings leaks whether lengths differ; comparing their
        # HMAC digests normalises to a fixed size before the constant-time XOR.
        digest = OpenSSL::Digest.new("SHA256")
        hmac_a = OpenSSL::HMAC.digest(digest, @secret, a)
        hmac_b = OpenSSL::HMAC.digest(digest, @secret, b)
        l = hmac_a.unpack("C*")
        r = hmac_b.unpack("C*")
        result = 0
        l.zip(r) { |x, y| result |= x ^ y }
        result.zero?
      end
    end
  end
end
