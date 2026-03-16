# frozen_string_literal: true

require "json"
require "set"
require "stringio"

module Whoosh
  class App
    attr_reader :config, :logger, :plugin_registry, :authenticator, :rate_limiter_instance, :token_tracker, :acl, :mcp_server, :mcp_manager, :instrumentation

    def initialize(root: Dir.pwd)
      @config = Config.load(root: root)
      @router = Router.new
      @middleware_stack = Middleware::Stack.new
      @di = DependencyInjection.new
      @error_handlers = {}
      @default_error_handler = nil
      @logger = Whoosh::Logger.new(
        format: @config.log_format.to_sym,
        level: @config.log_level.to_sym
      )
      @group_prefix = ""
      @group_middleware = []
      @plugin_registry = Plugins::Registry.new
      load_plugin_config
      @authenticator = nil
      @rate_limiter_instance = nil
      @token_tracker = Auth::TokenTracker.new
      @acl = Auth::AccessControl.new
      @instrumentation = Instrumentation.new
      @mcp_server = MCP::Server.new
      @mcp_manager = MCP::ClientManager.new
      @openapi_config = { title: "Whoosh API", version: Whoosh::VERSION }

      setup_default_middleware
    end

    # --- HTTP verb methods ---

    def get(path, **opts, &block)
      add_route("GET", path, **opts, &block)
    end

    def post(path, **opts, &block)
      add_route("POST", path, **opts, &block)
    end

    def put(path, **opts, &block)
      add_route("PUT", path, **opts, &block)
    end

    def patch(path, **opts, &block)
      add_route("PATCH", path, **opts, &block)
    end

    def delete(path, **opts, &block)
      add_route("DELETE", path, **opts, &block)
    end

    def options(path, **opts, &block)
      add_route("OPTIONS", path, **opts, &block)
    end

    # --- Route groups ---

    def group(prefix, middleware: [], &block)
      previous_prefix = @group_prefix
      previous_middleware = @group_middleware

      @group_prefix = "#{previous_prefix}#{prefix}"
      @group_middleware = previous_middleware + middleware

      instance_eval(&block)
    ensure
      @group_prefix = previous_prefix
      @group_middleware = previous_middleware
    end

    # --- Dependency injection ---

    def provide(name, scope: :singleton, &block)
      @di.provide(name, scope: scope, &block)
    end

    # --- Error handling ---

    def on_error(exception_class = nil, &block)
      if exception_class
        @error_handlers[exception_class] = block
      else
        @default_error_handler = block
      end
    end

    # --- Instrumentation ---

    def on_event(event, &block)
      @instrumentation.on(event, &block)
    end

    # --- Route listing ---

    def routes
      @router.routes
    end

    # --- Plugin DSL ---

    def plugin(name, enabled: true, **config)
      if enabled == false
        @plugin_registry.disable(name)
      else
        @plugin_registry.configure(name, config) unless config.empty?
      end
    end

    def setup_plugin_accessors
      @plugin_registry.define_accessors(self)
    end

    # --- Auth DSL ---

    def auth(&block)
      builder = AuthBuilder.new
      builder.instance_eval(&block)
      @authenticator = builder.build
    end

    def rate_limit(&block)
      builder = RateLimitBuilder.new
      builder.instance_eval(&block)
      @rate_limiter_instance = builder.build
    end

    def token_tracking(&block)
      builder = TokenTrackingBuilder.new(@token_tracker)
      builder.instance_eval(&block)
    end

    def access_control(&block)
      @acl.instance_eval(&block)
    end

    # --- MCP DSL ---

    def mcp_client(name, command:, **options)
      @mcp_manager.register(name, command: command, **options)
    end

    # --- OpenAPI DSL ---

    def openapi(&block)
      builder = OpenAPIConfigBuilder.new
      builder.instance_eval(&block)
      @openapi_config.merge!(builder.to_h)
    end

    # --- Health check ---

    def health_check(path: "/healthz", &block)
      probes = {}
      if block
        builder = HealthCheckBuilder.new
        builder.instance_eval(&block)
        probes = builder.probes
      end

      get path do
        checks = {}
        all_ok = true
        probes.each do |name, probe_block|
          begin
            probe_block.call
            checks[name.to_s] = "ok"
          rescue => e
            checks[name.to_s] = "fail: #{e.message}"
            all_ok = false
          end
        end

        result = { status: all_ok ? "ok" : "degraded", version: Whoosh::VERSION }
        result[:checks] = checks unless checks.empty?

        if all_ok
          result
        else
          [503, { "content-type" => "application/json" }, [Serialization::Json.encode(result)]]
        end
      end
    end

    # --- Streaming helpers ---

    def stream(type, &block)
      io = StringIO.new
      case type
      when :sse
        sse = Streaming::SSE.new(io)
        block.call(sse)
        io.rewind
        [200, Streaming::SSE.headers, [io.read]]
      else
        raise ArgumentError, "Unknown stream type: #{type}"
      end
    end

    def stream_llm(&block)
      io = StringIO.new
      llm_stream = Streaming::LlmStream.new(io)
      block.call(llm_stream)
      io.rewind
      [200, Streaming::LlmStream.headers, [io.read]]
    end

    # --- Endpoint loading ---

    def load_endpoints(dir)
      before = ObjectSpace.each_object(Class).select { |k| k < Endpoint }.to_set

      Dir.glob(File.join(dir, "**", "*.rb")).sort.each do |file|
        require file
      end

      after = ObjectSpace.each_object(Class).select { |k| k < Endpoint }.to_set
      (after - before).each { |klass| register_endpoint(klass) }
    end

    def register_endpoint(endpoint_class)
      endpoint_class.declared_routes.each do |route|
        handler = {
          block: nil,
          endpoint_class: endpoint_class,
          request_schema: route[:request_schema],
          response_schema: route[:response_schema],
          middleware: []
        }
        @router.add(route[:method], route[:path], handler, **route[:metadata])
      end
    end

    # --- Rack interface ---

    def to_rack
      @rack_app ||= begin
        @di.validate!
        register_mcp_tools
        register_doc_routes if @config.docs_enabled?
        @router.freeze!
        inner = method(:handle_request)
        @middleware_stack.build(inner)
      end
    end

    private

    def load_plugin_config
      root = @config.instance_variable_get(:@root)
      path = File.join(root, "config", "plugins.yml")
      return unless File.exist?(path)

      require "yaml"
      data = YAML.safe_load(File.read(path), permitted_classes: [Symbol]) || {}
      data.each do |accessor_name, config|
        name = accessor_name.to_sym
        if config.is_a?(Hash) && config["enabled"] == false
          @plugin_registry.disable(name)
        elsif config.is_a?(Hash)
          @plugin_registry.configure(name, config.reject { |k, _| k == "enabled" })
        end
      end
    end

    def setup_default_middleware
      @middleware_stack.use(Middleware::RequestLimit)
      @middleware_stack.use(Middleware::SecurityHeaders)
      @middleware_stack.use(Middleware::Cors)
      @middleware_stack.use(Middleware::RequestLogger, logger: @logger)
    end

    def register_mcp_tools
      @router.routes.each do |route|
        next unless route[:metadata] && route[:metadata][:mcp]

        tool_name = "#{route[:method]} #{route[:path]}"
        match = @router.match(route[:method], route[:path])
        next unless match

        handler_data = match[:handler]
        app_ref = self

        input_schema = if handler_data[:request_schema]
          OpenAPI::SchemaConverter.convert(handler_data[:request_schema])
        else
          {}
        end

        @mcp_server.register_tool(
          name: tool_name,
          description: tool_name,
          input_schema: input_schema,
          handler: ->(params) {
            env = Rack::MockRequest.env_for(route[:path], method: route[:method],
              input: JSON.generate(params), "CONTENT_TYPE" => "application/json")
            request = Request.new(env)

            if handler_data[:endpoint_class]
              handler_data[:endpoint_class].new.call(request)
            elsif handler_data[:block]
              app_ref.instance_exec(request, &handler_data[:block])
            end
          }
        )
      end
    end

    def register_doc_routes
      generator = OpenAPI::Generator.new(**@openapi_config)

      @router.routes.each do |route|
        match = @router.match(route[:method], route[:path])
        next unless match
        handler = match[:handler]
        generator.add_route(
          method: route[:method], path: route[:path],
          request_schema: handler[:request_schema],
          response_schema: handler[:response_schema]
        )
      end

      openapi_json = generator.to_json
      @router.add("GET", "/openapi.json", {
        block: -> (_req) { [200, { "content-type" => "application/json" }, [openapi_json]] },
        request_schema: nil, response_schema: nil, middleware: []
      })

      @router.add("GET", "/docs", {
        block: -> (_req) { OpenAPI::UI.rack_response("/openapi.json") },
        request_schema: nil, response_schema: nil, middleware: []
      })
    end

    def add_route(method, path, request: nil, response: nil, **metadata, &block)
      full_path = "#{@group_prefix}#{path}"
      handler = {
        block: block,
        request_schema: request,
        response_schema: response,
        middleware: @group_middleware.dup
      }
      @router.add(method, full_path, handler, **metadata)
    end

    def handle_request(env)
      request = Request.new(env)
      env["whoosh.logger"] = @logger
      match = @router.match(request.method, request.path)

      return Response.not_found unless match

      request.path_params = match[:params]
      handler = match[:handler]

      # Validate request schema
      if handler[:request_schema]
        body = request.body || {}
        result = handler[:request_schema].validate(body)
        unless result.success?
          return Response.error(Errors::ValidationError.new(result.errors))
        end
        request.instance_variable_set(:@body, result.data)
      end

      # Authenticate if route requires it
      if match[:metadata] && match[:metadata][:auth]
        raise Errors::UnauthorizedError, "No authenticator configured" unless @authenticator
        auth_result = @authenticator.authenticate(request)
        request.env["whoosh.auth"] = auth_result
      end

      # Rate limit check
      if @rate_limiter_instance
        key = request.env.dig("whoosh.auth", :key) || request.env["REMOTE_ADDR"] || "anonymous"
        @rate_limiter_instance.check!(key, request.path)
      end

      # Call handler
      if handler[:endpoint_class]
        # Class-based endpoint
        endpoint = handler[:endpoint_class].new
        context = Endpoint::Context.new(self, request)
        result = endpoint.call(context.request)
      else
        # Inline block endpoint
        block = handler[:block]
        block_params = block.parameters
        kwargs_names = block_params.select { |type, _| type == :keyreq || type == :key }.map(&:last)
        kwargs = @di.inject_for(kwargs_names, request: request)

        result = if kwargs.any? && block_params.any? { |type, _| type == :req || type == :opt }
          instance_exec(request, **kwargs, &block)
        elsif kwargs.any?
          instance_exec(**kwargs, &block)
        elsif block_params.any? { |type, _| type == :req || type == :opt }
          instance_exec(request, &block)
        else
          instance_exec(&block)
        end
      end

      if result.is_a?(Array) && result.length == 3 && result[0].is_a?(Integer)
        result
      else
        Response.json(result)
      end

    rescue Errors::HttpError => e
      Response.error(e)
    rescue => e
      @instrumentation.emit(:error, { error: e, path: request&.path, method: request&.method })
      handle_error(e, request)
    end

    def handle_error(error, request)
      # Check specific error handlers
      handler = @error_handlers.find { |klass, _| error.is_a?(klass) }&.last
      handler ||= @default_error_handler

      if handler
        result = handler.call(error, request)
        Response.json(result, status: 500)
      else
        Response.error(error, production: @config.production?)
      end
    end

    # --- DSL Builders ---

    class AuthBuilder
      def initialize
        @strategies = {}
      end

      def api_key(header: "X-Api-Key", keys: {})
        @strategies[:api_key] = Auth::ApiKey.new(keys: keys, header: header)
      end

      def jwt(secret:, algorithm: :hs256, expiry: 3600)
        @strategies[:jwt] = Auth::Jwt.new(secret: secret, algorithm: algorithm, expiry: expiry)
      end

      def build
        @strategies.values.first
      end
    end

    class RateLimitBuilder
      def initialize
        @default_limit = 60
        @default_period = 60
        @rules = []
        @tiers = []
        @on_store_failure = :fail_open
      end

      def default(limit:, period:)
        @default_limit = limit
        @default_period = period
      end

      def rule(path, limit:, period:)
        @rules << { path: path, limit: limit, period: period }
      end

      def tier(name, limit: nil, period: nil, unlimited: false)
        @tiers << { name: name, limit: limit, period: period, unlimited: unlimited }
      end

      def on_store_failure(strategy)
        @on_store_failure = strategy
      end

      def build
        limiter = Auth::RateLimiter.new(
          default_limit: @default_limit,
          default_period: @default_period,
          on_store_failure: @on_store_failure
        )
        @rules.each { |r| limiter.rule(r[:path], limit: r[:limit], period: r[:period]) }
        @tiers.each { |t| limiter.tier(t[:name], limit: t[:limit], period: t[:period], unlimited: t[:unlimited]) }
        limiter
      end
    end

    class TokenTrackingBuilder
      def initialize(tracker)
        @tracker = tracker
      end

      def on_usage(&block)
        @tracker.on_usage(&block)
      end
    end

    class HealthCheckBuilder
      attr_reader :probes
      def initialize
        @probes = {}
      end
      def probe(name, &block)
        @probes[name] = block
      end
    end

    class OpenAPIConfigBuilder
      def initialize
        @config = {}
      end

      def title(val)
        @config[:title] = val
      end

      def version(val)
        @config[:version] = val
      end

      def description(val)
        @config[:description] = val
      end

      def to_h
        @config
      end
    end
  end
end
