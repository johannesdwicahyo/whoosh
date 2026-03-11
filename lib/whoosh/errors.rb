# frozen_string_literal: true

module Whoosh
  module Errors
    class WhooshError < StandardError; end

    class HttpError < WhooshError
      attr_reader :status, :error_type

      def initialize(message = nil, status: 500, error_type: "internal_error")
        @status = status
        @error_type = error_type
        super(message || error_type)
      end

      def to_h
        { error: error_type }
      end
    end

    class ValidationError < HttpError
      attr_reader :details

      def initialize(details = [])
        @details = details
        super("Validation failed", status: 422, error_type: "validation_failed")
      end

      def to_h
        { error: error_type, details: details }
      end
    end

    class NotFoundError < HttpError
      def initialize(message = "Not found")
        super(message, status: 404, error_type: "not_found")
      end
    end

    class UnauthorizedError < HttpError
      def initialize(message = "Unauthorized")
        super(message, status: 401, error_type: "unauthorized")
      end
    end

    class ForbiddenError < HttpError
      def initialize(message = "Forbidden")
        super(message, status: 403, error_type: "forbidden")
      end
    end

    class RateLimitExceeded < HttpError
      attr_reader :retry_after

      def initialize(message = "Rate limit exceeded", retry_after: 60)
        @retry_after = retry_after
        super(message, status: 429, error_type: "rate_limited")
      end

      def to_h
        super.merge(retry_after: retry_after)
      end
    end

    class DependencyError < WhooshError; end
    class GuardrailsViolation < WhooshError; end
  end
end
