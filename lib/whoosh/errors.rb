module Whoosh
  class Error < StandardError; end

  # Raised while defining endpoints: a misconfigured endpoint stops the app
  # from booting instead of failing open in production.
  class DefinitionError < Error; end

  # Every HTTP error renders as the same envelope:
  #   { "error": { "code": "...", "message": "...", "details": {...}, "request_id": "..." } }
  class HTTPError < Error
    attr_reader :status, :code, :details, :headers

    def initialize(message = nil, status: 500, code: "internal_error", details: nil, headers: {})
      @status = status
      @code = code
      @details = details
      @headers = headers
      super(message || default_message)
    end

    def default_message = "Something went wrong."

    def to_h
      body = { code: code, message: message }
      body[:details] = details if details && !details.empty?
      body
    end
  end

  {
    BadRequest: [400, "bad_request", "The request couldn't be read."],
    Unauthorized: [401, "unauthorized", "Sign in or send a valid token."],
    Forbidden: [403, "forbidden", "You don't have permission to do that."],
    NotFound: [404, "not_found", "Not found."],
    MethodNotAllowed: [405, "method_not_allowed", "This path doesn't accept that method."],
    Conflict: [409, "conflict", "The request conflicts with the current state."],
    PayloadTooLarge: [413, "payload_too_large", "The request body is too large."],
    UnsupportedMediaType: [415, "unsupported_media_type", "Send the body as application/json."],
    UnprocessableEntity: [422, "validation_failed", "Some fields are invalid."],
    TooManyRequests: [429, "rate_limited", "Too many requests. Try again later."],
    InternalError: [500, "internal_error", "Something went wrong."]
  }.each do |name, (status, code, message)|
    klass = Class.new(HTTPError) do
      define_method(:initialize) do |msg = nil, details: nil, headers: {}, code: nil|
        super(msg || message, status: status, code: code || self.class::CODE, details: details, headers: headers)
      end
    end
    klass.const_set(:STATUS, status)
    klass.const_set(:CODE, code)
    const_set(name, klass)
  end

  # Input that fails its schema. details maps field paths to messages:
  #   { "items[0].quantity" => ["must be at least 1"] }
  class ValidationError < UnprocessableEntity
    def initialize(errors, message = nil)
      super(message, details: errors)
    end

    def errors = details
  end
end
