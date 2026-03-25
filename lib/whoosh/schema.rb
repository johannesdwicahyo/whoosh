# frozen_string_literal: true

require "dry-schema"
require "dry-types"

module Whoosh
  class Schema
    class Result
      attr_reader :data, :errors

      def initialize(data:, errors:)
        @data = data
        @errors = errors
      end

      def success?
        @errors.empty?
      end
    end

    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@fields, {})
        subclass.instance_variable_set(:@contract, nil)
        subclass.instance_variable_set(:@custom_validators, [])
      end

      def validate_with(&block)
        @custom_validators ||= []
        @custom_validators << block
      end

      def custom_validators
        @custom_validators || []
      end

      def field(name, type, **options)
        @fields[name] = options.merge(type: type)
        @contract = nil # Reset cached contract
      end

      def fields
        @fields
      end

      def validate(data)
        input = coerce_input(data)

        # First pass: dry-schema validation
        result = contract.call(input)

        unless result.success?
          errors = result.errors.to_h.flat_map do |field_name, messages|
            messages.map do |msg|
              { field: field_name, message: msg, value: input[field_name] || input[field_name.to_s] }
            end
          end
          return Result.new(data: nil, errors: errors)
        end

        validated = result.to_h

        # Second pass: min/max constraints + nested schema validation
        errors = []
        @fields.each do |name, opts|
          value = validated[name]
          next if value.nil?

          # Nested schema validation
          if schema_type?(opts[:type])
            nested_result = opts[:type].validate(value)
            unless nested_result.success?
              nested_result.errors.each do |err|
                errors << { field: :"#{name}.#{err[:field]}", message: err[:message], value: err[:value] }
              end
            else
              validated[name] = nested_result.data
            end
          end

          # Min/max constraints
          if opts[:min] && value.is_a?(Numeric) && value < opts[:min]
            errors << { field: name, message: "must be greater than or equal to #{opts[:min]}", value: value }
          end
          if opts[:max] && value.is_a?(Numeric) && value > opts[:max]
            errors << { field: name, message: "must be less than or equal to #{opts[:max]}", value: value }
          end
        end

        # Third pass: custom validators
        self.custom_validators.each do |validator|
          validator.call(validated, errors)
        end

        return Result.new(data: nil, errors: errors) unless errors.empty?

        Result.new(data: apply_defaults(validated), errors: [])
      end

      def serialize(data)
        return data unless data.is_a?(Hash)

        @fields.each_with_object({}) do |(name, opts), hash|
          value = data[name]
          if value.nil?
            hash[name] = opts[:default]
          elsif schema_type?(opts[:type])
            hash[name] = opts[:type].serialize(value)
          else
            hash[name] = serialize_value(value)
          end
        end
      end

      private

      def contract
        @contract ||= build_contract
      end

      def build_contract
        field_defs = @fields
        # Pre-classify each field type outside the DSL block (self = Schema class here)
        classified = field_defs.transform_values do |opts|
          type = opts[:type]
          if type.is_a?(Class) && type < Whoosh::Schema
            :nested_schema
          elsif type.is_a?(Dry::Types::Type)
            :dry_type
          else
            map_type(type)
          end
        end

        Dry::Schema.Params do
          field_defs.each do |name, opts|
            kind = classified[name]

            case kind
            when :nested_schema
              if opts[:required]
                required(name).filled(:hash)
              else
                optional(name).maybe(:hash)
              end
            when :dry_type
              if opts[:required]
                required(name).filled(:bool)
              else
                optional(name).maybe(:bool)
              end
            else
              if opts[:required]
                required(name).filled(kind)
              else
                optional(name).maybe(kind)
              end
            end
          end
        end
      end

      def map_type(type)
        case type.to_s
        when "String" then :string
        when "Integer" then :integer
        when "Float" then :float
        when "Hash" then :hash
        when "Array" then :array
        when "Time", "DateTime" then :time
        else :string
        end
      end

      def schema_type?(type)
        type.is_a?(Class) && type < Whoosh::Schema
      rescue TypeError
        false
      end

      def coerce_input(data)
        return {} if data.nil?

        data.transform_keys(&:to_sym)
      end

      def apply_defaults(data)
        @fields.each do |name, opts|
          if data[name].nil? && opts.key?(:default)
            data[name] = opts[:default]
          end
        end
        data
      end

      def serialize_value(value)
        case value
        when Time, DateTime
          value.iso8601
        when BigDecimal
          value.to_s("F")
        else
          value
        end
      end
    end
  end
end
