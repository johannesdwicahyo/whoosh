module Whoosh
  # The Rack application. Holds the compiled router for one or more API
  # classes and runs every request through the same pipeline:
  #
  #   request id -> CORS preflight -> route -> authenticate -> rate limit
  #   -> 401 unless public -> parse params -> authorize -> idempotency
  #   -> handler -> serialize through `returns` -> security headers
  class App
    SECURITY_HEADERS = {
      "x-content-type-options" => "nosniff",
      "x-frame-options" => "DENY",
      "referrer-policy" => "no-referrer",
      "content-security-policy" => "default-src 'none'; frame-ancestors 'none'",
      "cross-origin-opener-policy" => "same-origin",
      "cache-control" => "no-store"
    }.freeze
    JSON_CONTENT_TYPE = "application/json; charset=utf-8".freeze
    CORS_ALLOWED_HEADERS = %w[authorization content-type idempotency-key x-request-id accept].freeze
    OPENAPI_PATH = "/openapi.json".freeze

    AR_NOT_FOUND = "ActiveRecord::RecordNotFound".freeze
    AR_INVALID = "ActiveRecord::RecordInvalid".freeze
    AR_NOT_UNIQUE = "ActiveRecord::RecordNotUnique".freeze
    AR_STALE = "ActiveRecord::StaleObjectError".freeze

    attr_reader :apis, :router

    def initialize(apis, config: nil)
      @apis = apis
      @config_override = config
      @router = Router.new
      apis.each do |api|
        api.endpoints.each { |ep| @router.add(ep.verb, ep.path, ep) }
      end
      @openapi_json = nil
    end

    def config = @config_override || Whoosh.config

    def call(env)
      request = Request.new(env, config)
      status, headers, body = dispatch(request)
      finish(request, status, headers, body)
    end

    private

    # ---- dispatch ----------------------------------------------------------

    def dispatch(request)
      return preflight(request) if request.request_method == "OPTIONS"
      return openapi(request) if serve_openapi?(request)

      match = @router.match(request.request_method, request.path)
      raise NotFound.new("No endpoint matches #{request.request_method} #{request.path}.") if match.nil?

      if match.first == :method_not_allowed
        allow = (match.last + (match.last.include?("GET") ? ["HEAD"] : []) + ["OPTIONS"]).join(", ")
        raise MethodNotAllowed.new(headers: { "allow" => allow })
      end

      endpoint, path_params = match
      run(endpoint, request, path_params)
    rescue HTTPError => e
      error_response(request, e)
    rescue StandardError => e
      error_response(request, translate(e, request))
    end

    def run(endpoint, request, path_params)
      user = authenticate(request)
      request.user_id_for_limits = user_key(user)
      client = config.client_identifier.call(request).to_s
      limit_headers = check_rate_limit(endpoint, client)

      raise Unauthorized if user.nil? && !endpoint.public?

      context = endpoint.api.context_class.new(request, endpoint, user)
      params = parse_params(endpoint, request, path_params)
      context.assign_params(params)

      if endpoint.authorizer && !context.instance_exec(user, params, &endpoint.authorizer)
        raise Forbidden
      end

      execute = lambda do
        result = context.instance_exec(params, &endpoint.handler)
        render(endpoint, context, request, result)
      end

      status, headers, body =
        if endpoint.idempotency
          Idempotency.new(config.store, ttl: config.idempotency_ttl)
                     .call(request, scope: endpoint.id, client: client, required: endpoint.idempotency[:required], &execute)
        else
          execute.call
        end
      [status, headers.merge(limit_headers), body]
    end

    def authenticate(request)
      config.authenticate&.call(request)
    rescue HTTPError
      raise
    end

    def user_key(user)
      return nil if user.nil?

      id = user.respond_to?(:id) ? user.id : user.object_id
      "user:#{id}"
    end

    def check_rate_limit(endpoint, client)
      limit, per = endpoint.effective_rate_limit(config)
      return {} unless limit

      result = RateLimiter.new(config.store).check!(endpoint.id, client, limit: limit, per: per)
      { "x-ratelimit-limit" => result.limit.to_s, "x-ratelimit-remaining" => result.remaining.to_s }
    end

    def parse_params(endpoint, request, path_params)
      schema = endpoint.params_schema
      return {}.freeze unless schema

      input = request.query
      input = input.except(*endpoint.pagination.query_fields) if endpoint.pagination
      input = input.merge(request.json) if request.body?
      input = input.merge(path_params) unless path_params.empty?
      schema.parse(input)
    end

    def render(endpoint, context, request, result)
      status = context.status || endpoint.status
      headers = context.response_headers.dup
      return [status, headers, []] if endpoint.no_content?

      schema = endpoint.returns_schema
      payload =
        if endpoint.pagination
          page = endpoint.pagination.call(result, request.query, config)
          { "data" => schema.dump_many(page.records), "meta" => page.meta }
        elsif endpoint.many?
          { "data" => schema.dump_many(result.respond_to?(:to_a) ? result.to_a : Array(result)) }
        else
          raise NotFound if result.nil?

          { "data" => schema.dump(result) }
        end
      json_response(status, payload, headers)
    end

    # ---- errors ------------------------------------------------------------

    def translate(exception, request)
      custom = rescue_handler_for(exception, request)
      return custom if custom

      case exception.class.name
      when AR_NOT_FOUND then NotFound.new
      when AR_INVALID then ValidationError.new(record_errors(exception))
      when AR_NOT_UNIQUE then Conflict.new("A record with these values already exists.")
      when AR_STALE then Conflict.new("This record was changed by someone else. Reload and try again.")
      else
        report(exception, request)
        if config.expose_errors
          InternalError.new("#{exception.class}: #{exception.message}",
                            details: { "backtrace" => Array(exception.backtrace).first(15) })
        else
          InternalError.new
        end
      end
    end

    def rescue_handler_for(exception, request)
      apis.each do |api|
        api.rescue_handlers.each do |klass, handler|
          next unless exception.is_a?(klass)

          result = handler.call(exception, request)
          return result if result.is_a?(HTTPError)
        end
      end
      nil
    end

    def record_errors(exception)
      record = exception.respond_to?(:record) ? exception.record : nil
      return {} unless record && record.respond_to?(:errors)

      record.errors.to_hash.each_with_object({}) { |(k, v), h| h[k.to_s] = Array(v) }
    end

    def report(exception, request)
      config.logger&.error("[whoosh] #{request.request_id} #{exception.class}: #{exception.message}\n" \
                           "#{Array(exception.backtrace).first(20).join("\n")}")
      config.on_error&.call(exception, request)
    rescue StandardError
      nil
    end

    def error_response(request, error)
      body = { "error" => error.to_h.transform_keys(&:to_s).merge("request_id" => request.request_id) }
      json_response(error.status, body, error.headers.dup)
    end

    # ---- CORS, OpenAPI, headers -------------------------------------------

    def preflight(request)
      headers = {}
      verbs = methods_for(request.path)
      verbs += ["HEAD"] if verbs.include?("GET")
      headers["allow"] = (verbs + ["OPTIONS"]).join(", ") unless verbs.empty?

      if cors_allowed?(request.origin) && request.header("access-control-request-method")
        headers["access-control-allow-methods"] = (verbs.empty? ? Endpoint::VERBS : verbs).join(", ")
        requested = request.header("access-control-request-headers").to_s.downcase.split(/\s*,\s*/)
        headers["access-control-allow-headers"] = (requested & CORS_ALLOWED_HEADERS).join(", ")
        headers["access-control-max-age"] = config.cors_max_age.to_s
      end
      [204, headers, []]
    end

    def methods_for(path)
      Endpoint::VERBS.select do |verb|
        m = @router.match(verb, path)
        m && m.first != :method_not_allowed
      end
    end

    def cors_allowed?(origin)
      return false if origin.nil? || origin.empty?

      config.cors_origins.any? do |allowed|
        allowed.is_a?(Regexp) ? allowed.match?(origin) : allowed == origin
      end
    end

    def serve_openapi?(request)
      config.openapi && request.request_method.match?(/\A(GET|HEAD)\z/) && request.path == OPENAPI_PATH
    end

    def openapi(request)
      if config.openapi == :authenticated && authenticate(request).nil?
        raise Unauthorized
      end

      @openapi_json ||= Whoosh::JSON.dump(OpenAPI.new(apis, server_url: request.script_name).document)
      [200, { "content-type" => JSON_CONTENT_TYPE, "cache-control" => "no-cache" }, [@openapi_json]]
    end

    def json_response(status, payload, headers)
      body = Whoosh::JSON.dump(payload)
      headers["content-type"] = JSON_CONTENT_TYPE
      [status, headers, [body]]
    end

    def finish(request, status, headers, body)
      out = SECURITY_HEADERS.merge(config.default_headers).merge(headers)
      out["x-request-id"] = request.request_id
      out["strict-transport-security"] = "max-age=63072000; includeSubDomains" if request.https?

      origin = request.origin
      if cors_allowed?(origin)
        out["access-control-allow-origin"] = origin
        out["access-control-allow-credentials"] = "true" if config.cors_credentials
        out["access-control-expose-headers"] = config.cors_expose_headers.join(", ")
      end
      out["vary"] = [out["vary"], "origin"].compact.join(", ") if config.cors_origins.any?

      if status == 204 || status == 304
        out.delete("content-type")
        body = []
      end
      out["content-length"] = body.sum(&:bytesize).to_s if body.is_a?(Array)
      body = [] if request.head?
      [status, out, body]
    end
  end
end
