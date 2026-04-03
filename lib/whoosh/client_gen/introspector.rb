# frozen_string_literal: true

require "whoosh/client_gen/ir"
require "whoosh/openapi/schema_converter"

module Whoosh
  module ClientGen
    class Introspector
      AUTH_PATH_PREFIX = "/auth/"
      INTERNAL_PATHS = %w[/openapi.json /docs /redoc /metrics /healthz].freeze

      ACTION_MAP = {
        "GET" => ->(path) { path.include?("/:") || path.include?("/{") ? :show : :index },
        "POST" => ->(_path) { :create },
        "PUT" => ->(_path) { :update },
        "PATCH" => ->(_path) { :update },
        "DELETE" => ->(_path) { :destroy }
      }.freeze

      AUTH_ENDPOINT_MAP = {
        "login" => :login,
        "register" => :register,
        "signup" => :register,
        "refresh" => :refresh,
        "logout" => :logout,
        "me" => :me
      }.freeze

      def initialize(app, base_url: "http://localhost:9292")
        @app = app
        @base_url = base_url
        @router = app.instance_variable_get(:@router)
      end

      def introspect
        routes = @router.routes
        auth_routes, resource_routes = partition_routes(routes)

        auth = detect_auth(auth_routes)
        resources = group_resources(resource_routes)
        streaming = detect_streaming(resource_routes)

        IR::AppSpec.new(
          auth: auth,
          resources: resources,
          streaming: streaming,
          base_url: @base_url
        )
      end

      private

      def partition_routes(routes)
        filtered = routes.reject { |r| INTERNAL_PATHS.include?(r[:path]) }
        filtered.partition { |r| r[:path].start_with?(AUTH_PATH_PREFIX) }
      end

      def detect_auth(auth_routes)
        return nil if auth_routes.empty? && @app.authenticator.nil?

        auth_type = detect_auth_type
        endpoints = {}

        auth_routes.each do |route|
          segment = route[:path].sub(AUTH_PATH_PREFIX, "").split("/").first
          key = AUTH_ENDPOINT_MAP[segment]
          next unless key
          endpoints[key] = { method: route[:method].downcase.to_sym, path: route[:path] }
        end

        return nil if auth_type.nil? && endpoints.empty?

        oauth_providers = detect_oauth_providers(auth_routes)

        IR::Auth.new(type: auth_type, endpoints: endpoints, oauth_providers: oauth_providers)
      end

      def detect_auth_type
        authenticator = @app.authenticator
        return nil unless authenticator

        class_name = authenticator.class.name.to_s.downcase
        return :jwt if class_name.include?("jwt")
        return :api_key if class_name.include?("apikey") || class_name.include?("api_key")
        return :oauth2 if class_name.include?("oauth")

        :jwt # default assumption
      end

      def detect_oauth_providers(auth_routes)
        providers = []
        auth_routes.each do |route|
          path = route[:path]
          %i[google github apple].each do |provider|
            providers << provider if path.include?(provider.to_s)
          end
        end
        providers.uniq
      end

      def group_resources(routes)
        grouped = {}

        routes.each do |route|
          resource_name = extract_resource_name(route[:path])
          next unless resource_name

          grouped[resource_name] ||= { endpoints: [], fields: {} }
          action = ACTION_MAP[route[:method]]&.call(route[:path]) || :custom

          # Get handler details via router match
          handler = resolve_handler(route)

          endpoint = IR::Endpoint.new(
            method: route[:method].downcase.to_sym,
            path: route[:path],
            action: action,
            request_schema: handler&.dig(:request_schema)&.name&.to_sym,
            response_schema: handler&.dig(:response_schema)&.name&.to_sym
          )
          grouped[resource_name][:endpoints] << endpoint

          if handler&.dig(:request_schema)
            extract_fields(handler[:request_schema], grouped[resource_name][:fields])
          end
          if handler&.dig(:response_schema)
            extract_fields(handler[:response_schema], grouped[resource_name][:fields])
          end
        end

        grouped.map do |name, data|
          IR::Resource.new(
            name: name.to_sym,
            endpoints: data[:endpoints],
            fields: data[:fields].values
          )
        end
      end

      def resolve_handler(route)
        match = @router.match(route[:method], route[:path])
        match[:handler] if match
      end

      def extract_resource_name(path)
        segments = path.split("/").reject(&:empty?)
        return nil if segments.empty?
        # Find the first non-param segment
        segments.find { |s| !s.start_with?(":") }
      end

      def extract_fields(schema_class, fields_hash)
        return unless schema_class.respond_to?(:fields)

        schema_class.fields.each do |name, opts|
          type = opts[:type]
          openapi_type = OpenAPI::SchemaConverter.type_for(type)

          fields_hash[name] = {
            name: name,
            type: openapi_type.to_sym,
            required: opts[:required] || false,
            desc: opts[:desc],
            enum: opts[:enum],
            default: opts[:default],
            min: opts[:min],
            max: opts[:max]
          }.compact
        end
      end

      def detect_streaming(routes)
        routes.select { |r| r.dig(:metadata, :stream) || r.dig(:metadata, :sse) }
              .map { |r| { path: r[:path], type: :sse } }
      end
    end
  end
end
