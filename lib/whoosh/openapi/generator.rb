# frozen_string_literal: true

require "json"

module Whoosh
  module OpenAPI
    class Generator
      def initialize(title: "Whoosh API", version: "0.1.0", description: nil)
        @title = title
        @version = version
        @description = description
        @paths = {}
      end

      def add_route(method:, path:, request_schema: nil, response_schema: nil, query_schema: nil, description: nil)
        openapi_path = path.gsub(/:(\w+)/, '{\1}')
        http_method = method.downcase.to_sym
        @paths[openapi_path] ||= {}
        operation = { summary: description || "#{method} #{path}" }

        params = path.scan(/:(\w+)/).flatten
        unless params.empty?
          operation[:parameters] = params.map { |p| { name: p, in: "path", required: true, schema: { type: "string" } } }
        end

        if query_schema
          qs = SchemaConverter.convert(query_schema)
          (qs[:properties] || {}).each do |name, prop|
            operation[:parameters] ||= []
            operation[:parameters] << {
              name: name.to_s, in: "query",
              required: qs[:required]&.include?(name) || false,
              schema: prop, description: prop[:description]
            }
          end
        end

        if request_schema
          operation[:requestBody] = {
            required: true,
            content: { "application/json" => { schema: SchemaConverter.convert(request_schema) } }
          }
        end

        operation[:responses] = { "200" => { description: "Successful response",
          content: { "application/json" => { schema: response_schema ? SchemaConverter.convert(response_schema) : { type: "object" } } } } }

        @paths[openapi_path][http_method] = operation
      end

      def generate
        spec = { openapi: "3.1.0", info: { title: @title, version: @version }, paths: @paths }
        spec[:info][:description] = @description if @description
        spec
      end

      def to_json
        JSON.generate(generate)
      end
    end
  end
end
