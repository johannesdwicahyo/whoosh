# frozen_string_literal: true

require "json"
require "set"
require "stringio"

module Whoosh
  class App
    attr_reader :config, :logger, :plugin_registry, :authenticator, :rate_limiter_instance, :token_tracker, :acl, :mcp_server, :mcp_manager

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
      @authenticator = nil
      @rate_limiter_instance = nil
      @token_tracker = Auth::TokenTracker.new
      @acl = Auth::AccessControl.new
      @mcp_server = MCP::Server.new
      @mcp_manager = MCP::ClientManager.new

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
        @router.freeze!
        inner = method(:handle_request)
        @middleware_stack.build(inner)
      end
    end

    private

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

        @mcp_server.register_tool(
          name: tool_name,
          description: tool_name,
          input_schema: {},
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
  end
end
