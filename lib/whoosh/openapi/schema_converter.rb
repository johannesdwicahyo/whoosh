# frozen_string_literal: true

module Whoosh
  module OpenAPI
    class SchemaConverter
      TYPE_MAP = {
        "String" => "string", "Integer" => "integer", "Float" => "number",
        "Hash" => "object", "Array" => "array", "Time" => "string", "DateTime" => "string"
      }.freeze

      def self.convert(schema_class)
        return {} unless schema_class.respond_to?(:fields)
        properties = {}
        required = []

        schema_class.fields.each do |name, opts|
          type = opts[:type]
          if type.is_a?(Class) && type < Schema
            properties[name] = convert(type)
          else
            prop = { type: type_for(type) }
            prop[:description] = opts[:desc] if opts[:desc]
            prop[:default] = opts[:default] if opts.key?(:default)
            prop[:minimum] = opts[:min] if opts[:min]
            prop[:maximum] = opts[:max] if opts[:max]
            prop[:format] = "date-time" if type == Time || type == DateTime
            properties[name] = prop
          end
          required << name if opts[:required]
        end

        result = { type: "object", properties: properties }
        result[:required] = required unless required.empty?
        result
      end

      def self.type_for(type)
        # Check for Dry::Types (Bool)
        begin
          return "boolean" if type.is_a?(Dry::Types::Type)
        rescue
          # ignore if Dry::Types not available
        end
        TYPE_MAP[type.to_s] || "string"
      end
    end
  end
end
