# frozen_string_literal: true

module Whoosh
  class Endpoint
    class Context
      attr_reader :request

      def initialize(app, request)
        @app = app
        @request = request
      end

      def respond_to_missing?(method_name, include_private = false)
        @app.respond_to?(method_name, include_private) || super
      end

      private

      def method_missing(method_name, ...)
        if @app.respond_to?(method_name)
          @app.send(method_name, ...)
        else
          super
        end
      end
    end

    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@declared_routes, [])
      end

      def declared_routes
        @declared_routes
      end

      def get(path, **opts)
        declare_route("GET", path, **opts)
      end

      def post(path, **opts)
        declare_route("POST", path, **opts)
      end

      def put(path, **opts)
        declare_route("PUT", path, **opts)
      end

      def patch(path, **opts)
        declare_route("PATCH", path, **opts)
      end

      def delete(path, **opts)
        declare_route("DELETE", path, **opts)
      end

      def options(path, **opts)
        declare_route("OPTIONS", path, **opts)
      end

      private

      def declare_route(method, path, request: nil, response: nil, **metadata)
        @declared_routes << {
          method: method,
          path: path,
          request_schema: request,
          response_schema: response,
          metadata: metadata
        }
      end
    end

    def call(req)
      raise NotImplementedError, "#{self.class}#call must be implemented"
    end
  end
end
