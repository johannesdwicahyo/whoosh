# frozen_string_literal: true

require "json"
require "set"

module Whoosh
  class App
    attr_reader :config, :logger, :plugin_registry

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

      Response.json(result)

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
  end
end
