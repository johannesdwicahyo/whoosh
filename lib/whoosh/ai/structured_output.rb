# frozen_string_literal: true

module Whoosh
  module AI
    # Validates LLM output against a Whoosh::Schema
    module StructuredOutput
      def self.validate(data, schema:)
        result = schema.validate(data)
        return result.data if result.success?
        raise Errors::ValidationError.new(result.errors)
      end

      def self.prompt_for(schema)
        return "" unless schema.respond_to?(:fields)

        lines = schema.fields.map do |name, opts|
          type = OpenAPI::SchemaConverter.type_for(opts[:type])
          parts = ["#{name}: #{type}"]
          parts << "(required)" if opts[:required]
          parts << "— #{opts[:desc]}" if opts[:desc]
          parts << "[min: #{opts[:min]}]" if opts[:min]
          parts << "[max: #{opts[:max]}]" if opts[:max]
          parts << "[default: #{opts[:default]}]" if opts.key?(:default)
          "  #{parts.join(" ")}"
        end

        "Return ONLY valid JSON matching this schema:\n{\n#{lines.join(",\n")}\n}"
      end
    end
  end
end
