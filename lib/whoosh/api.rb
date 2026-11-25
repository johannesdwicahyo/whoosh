module Whoosh
  # Subclass to define endpoints. Each subclass is a Rack app.
  #
  #   class ApplicationAPI < Whoosh::API
  #     version 1
  #     helpers do
  #       def current_store = current_user.store
  #     end
  #   end
  #
  #   class OrdersAPI < ApplicationAPI
  #     get "/orders" do
  #       authorize { |user| user.staff? }
  #       paginate
  #       returns OrderSchema
  #       handle { current_store.orders }
  #     end
  #   end
  class API
    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@path_prefix, path_prefix)
        subclass.instance_variable_set(:@helper_modules, helper_modules.dup)
        subclass.instance_variable_set(:@rescue_handlers, rescue_handlers.dup)
        subclass.instance_variable_set(:@default_tags, default_tags.dup)
        subclass.instance_variable_set(:@info, info.dup)
        subclass.instance_variable_set(:@endpoints, [])
        subclass.instance_variable_set(:@definition_router, nil)
      end

      # Prefixes every path with /v<n>. Declare before any endpoint.
      def version(number)
        set_prefix("#{path_prefix}/v#{Integer(number)}")
      end

      # Prefixes every path. Declare before any endpoint.
      def prefix(path)
        set_prefix("#{path_prefix}/#{path.to_s.delete_prefix('/').chomp('/')}")
      end

      def path_prefix = @path_prefix || ""

      # Methods available inside authorize and handle blocks.
      #   helpers do
      #     def current_store = current_user.store
      #   end
      #   helpers StoreHelpers
      def helpers(mod = nil, &block)
        helper_modules << mod if mod
        helper_modules << Module.new(&block) if block
        @context_class = nil
      end

      def helper_modules = (@helper_modules ||= [])

      # Map your own exceptions to responses. Return a Whoosh::HTTPError.
      #   rescue_from(Xendit::CardDeclined) { |e| Whoosh::HTTPError.new(e.message, status: 402, code: "card_declined") }
      def rescue_from(*classes, &block)
        raise DefinitionError, "rescue_from needs a block" unless block

        classes.each { |klass| rescue_handlers << [klass, block] }
      end

      def rescue_handlers = (@rescue_handlers ||= [])

      # Default OpenAPI tag for this class's endpoints.
      def tag(*names)
        @default_tags = names.flatten.map(&:to_s)
      end

      def default_tags = (@default_tags ||= [])

      # Title, version and description for the OpenAPI document.
      def openapi_info(**values)
        info.merge!(values.transform_keys(&:to_s))
      end

      def info = (@info ||= {})

      Endpoint::VERBS.each do |verb|
        define_method(verb.downcase) do |path, &block|
          define_endpoint(verb, path, &block)
        end
      end

      def endpoints = (@endpoints ||= [])

      def context_class
        @context_class ||= begin
          modules = helper_modules
          Class.new(Context) { modules.each { |m| include m } }
        end
      end

      # The Rack interface: `run OrdersAPI` or `mount OrdersAPI => "/api"`.
      def call(env)
        (@app ||= App.new([self])).call(env)
      end

      def routes
        endpoints.map { |ep| [ep.verb, ep.path] }
      end

      def openapi(**options)
        OpenAPI.new([self], **options).document
      end

      private

      def set_prefix(value)
        raise DefinitionError, "#{name}: declare version/prefix before any endpoint" if endpoints.any?

        @path_prefix = value
      end

      def define_endpoint(verb, path, &block)
        raise DefinitionError, "#{name} #{verb} #{path}: endpoints need a block" unless block

        full = "#{path_prefix}/#{path.to_s.delete_prefix('/')}".chomp("/")
        full = "/" if full.empty?
        endpoint = Endpoint.new(self, verb, full)
        endpoint.instance_eval(&block)
        endpoint.tags(*default_tags) if endpoint.docs[:tags].nil? && default_tags.any?
        endpoint.finalize!
        # Fails now (at boot) on duplicate routes or conflicting param names.
        (@definition_router ||= Router.new).add(verb, full, endpoint)
        endpoints << endpoint
        @app = nil
        endpoint
      end
    end
  end
end
