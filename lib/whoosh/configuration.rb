module Whoosh
  # Global settings. Every default is the safe choice; loosen them explicitly.
  class Configuration
    # ->(request) { User.find_by_token(request.bearer_token) }
    # Returns the user, or nil for an anonymous request. Endpoints that aren't
    # `public` respond 401 when it returns nil.
    attr_accessor :authenticate

    # Exact origins allowed for CORS, e.g. ["https://app.example.com"].
    # Empty means no cross-origin access. "*" is refused for credentialed CORS.
    attr_accessor :cors_origins, :cors_max_age, :cors_credentials, :cors_expose_headers

    # Largest request body accepted, in bytes.
    attr_accessor :max_body_size

    # Default and maximum page sizes for paginated endpoints.
    attr_accessor :default_page_size, :max_page_size

    # Default limit for every endpoint: [requests, per_seconds]. nil turns it off.
    attr_accessor :rate_limit

    # Stores for rate limits and idempotency keys. Use a shared store
    # (Whoosh::Stores::Cache.new(Rails.cache)) when running several processes.
    attr_accessor :store

    # How long a replayable idempotent response is kept, in seconds.
    attr_accessor :idempotency_ttl

    # Show exception messages and backtraces in 500 responses. Development only.
    attr_accessor :expose_errors

    # Serve the OpenAPI document at GET /openapi.json on each API.
    attr_accessor :openapi

    # Header used for request IDs; an incoming one is kept if it looks safe.
    attr_accessor :request_id_header

    # Extra response headers merged into every response.
    attr_accessor :default_headers

    # ->(exception, request) { Sentry.capture_exception(exception) }
    attr_accessor :on_error

    # Anything that responds to #info/#error. Rails sets Rails.logger.
    attr_accessor :logger

    # Maximum nesting depth and number of keys accepted in JSON bodies.
    attr_accessor :max_json_depth, :max_json_keys

    # Which address to key rate limits on: ->(request) { request.ip }.
    attr_accessor :client_identifier

    def initialize
      @authenticate = ->(_request) { nil }
      @cors_origins = []
      @cors_max_age = 600
      @cors_credentials = false
      @cors_expose_headers = %w[x-request-id retry-after x-ratelimit-limit x-ratelimit-remaining]
      @max_body_size = 1_048_576 # 1 MB
      @default_page_size = 25
      @max_page_size = 100
      @rate_limit = [300, 60]
      @store = Stores::Memory.new
      @idempotency_ttl = 24 * 60 * 60
      @expose_errors = false
      @openapi = false
      @request_id_header = "x-request-id"
      @default_headers = {}
      @on_error = nil
      @logger = nil
      @max_json_depth = 20
      @max_json_keys = 1_000
      @client_identifier = ->(request) { request.user_id_for_limits || request.ip }
    end
  end
end
