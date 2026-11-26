module Whoosh
  # Describes the shape of input or output. The same schema validates and
  # coerces request input, serializes responses (only declared fields ever
  # leave the server), and documents both in OpenAPI.
  #
  #   class LineItemSchema < Whoosh::Schema
  #     field :product_id, :integer, required: true
  #     field :quantity, :integer, required: true, min: 1, max: 999
  #   end
  #
  #   class OrderSchema < Whoosh::Schema
  #     field :id, :integer
  #     field :number, :string
  #     field :total, :decimal
  #     field :status, :string, enum: %w[pending paid cancelled]
  #     field :customer, CustomerSchema
  #     field :items, :array, of: LineItemSchema, from: :line_items
  #   end
  class Schema
    # Largest array accepted on input when a field doesn't set max_items.
    DEFAULT_MAX_ITEMS = 100
    FIELD_OPTIONS = %i[required default nullable enum min max min_length max_length min_items max_items scale
                       format of from description example deprecated].freeze

    class Field
      attr_reader :name, :key, :type, :schema, :options

      def initialize(name, type, options)
        @name = name.to_sym
        @key = name.to_s
        @options = options
        if type.is_a?(Class) && type <= Schema
          @type = :object
          @schema = type
        else
          @type = type.to_sym
          @schema = options[:schema]
        end
      end

      def required? = !!options[:required]
      def nullable? = !!options[:nullable]
      def default? = options.key?(:default)

      def default
        value = options[:default]
        value.respond_to?(:call) ? value.call : value
      end

      def item_type = options[:of]
      def item_schema? = item_type.is_a?(Class) && item_type <= Schema
    end

    class << self
      def fields
        @fields ||= {}
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@fields, fields.dup)
        subclass.instance_variable_set(:@reject_unknown, @reject_unknown)
      end

      # Build an anonymous schema from a block.
      def build(name = nil, &block)
        klass = Class.new(self)
        klass.instance_variable_set(:@anonymous_name, name)
        klass.class_eval(&block) if block
        klass
      end

      def schema_name
        name || @anonymous_name
      end

      #   field :email, :email, required: true
      #   field :address, :object do
      #     field :city, :string
      #   end
      #   field :tags, :array, of: :string, max_items: 10
      def field(name, type = :string, **options, &block)
        unknown = options.keys - FIELD_OPTIONS - [:schema]
        raise DefinitionError, "#{self.name || 'Schema'}.#{name}: unknown option(s) #{unknown.join(', ')}" if unknown.any?

        if block
          nested = Schema.build("#{schema_name}#{name.to_s.split('_').map(&:capitalize).join}", &block)
          if type.to_sym == :array
            options = options.merge(of: nested)
          else
            type = nested
          end
        end
        validate_type!(name, type, options)
        fields[name.to_sym] = Field.new(name, type, options)
      end

      def required(name, type = :string, **options, &block)
        field(name, type, **options, required: true, &block)
      end

      def optional(name, type = :string, **options, &block)
        field(name, type, **options, required: false, &block)
      end

      # Respond 422 when the input has keys the schema doesn't declare.
      # By default unknown keys are silently dropped.
      def reject_unknown!
        @reject_unknown = true
      end

      def reject_unknown? = !!@reject_unknown

      # ---- input -----------------------------------------------------------

      # Validates and coerces a Hash of input. Returns a frozen Hash with
      # symbol keys, or raises ValidationError with every problem found.
      def parse(input)
        errors = {}
        result = parse_object(input, "", errors)
        raise ValidationError.new(errors) unless errors.empty?

        result
      end

      def parse_object(input, path, errors)
        unless input.is_a?(Hash)
          add_error(errors, path, "must be an object")
          return nil
        end

        if reject_unknown?
          (input.keys.map(&:to_s) - fields.keys.map(&:to_s)).each do |key|
            add_error(errors, join(path, key), "is not allowed")
          end
        end

        result = {}
        fields.each_value do |field|
          present = input.key?(field.key) || input.key?(field.name)
          raw = input.key?(field.key) ? input[field.key] : input[field.name]

          unless present
            if field.default? then result[field.name] = field.default
            elsif field.required? then add_error(errors, join(path, field.key), "is required")
            end
            next
          end

          if raw.nil? || (raw == "" && field.type != :string && field.type != :text)
            if field.nullable? || (!field.required? && raw.nil?)
              result[field.name] = nil if field.nullable?
            else
              add_error(errors, join(path, field.key), field.required? ? "is required" : "can't be null")
            end
            next
          end

          value = parse_value(field, raw, join(path, field.key), errors)
          result[field.name] = value unless value.equal?(INVALID)
        end
        result.freeze
      end

      INVALID = Object.new.freeze

      def parse_value(field, raw, path, errors)
        value =
          case field.type
          when :object
            return parse_nested(field.schema, raw, path, errors)
          when :array
            return parse_array(field, raw, path, errors)
          else
            Types.coerce(field.type, raw)
          end
        check_constraints(field, value, path, errors)
      rescue Types::Invalid => e
        add_error(errors, path, e.message)
        INVALID
      end

      def parse_nested(schema, raw, path, errors)
        before = errors.size
        value = schema.parse_object(raw, path, errors)
        errors.size == before ? value : INVALID
      end

      def parse_array(field, raw, path, errors)
        raw = raw.values if raw.is_a?(Hash) && raw.keys.all? { |k| k.to_s.match?(/\A\d+\z/) } # form-style a[0]=..
        unless raw.is_a?(Array)
          add_error(errors, path, "must be a list")
          return INVALID
        end
        max = field.options.fetch(:max_items, DEFAULT_MAX_ITEMS)
        min = field.options[:min_items]
        add_error(errors, path, "must have at most #{max} items") if raw.size > max
        add_error(errors, path, "must have at least #{min} items") if min && raw.size < min
        return INVALID if raw.size > max

        before = errors.size
        items = raw.each_with_index.map do |item, i|
          item_path = "#{path}[#{i}]"
          if field.item_schema?
            field.item_type.parse_object(item, item_path, errors)
          elsif field.item_type
            begin
              value = Types.coerce(field.item_type.to_sym, item)
              check_constraints(field, value, item_path, errors, item: true)
            rescue Types::Invalid => e
              add_error(errors, item_path, e.message)
              nil
            end
          else
            raise DefinitionError, "#{schema_name}.#{field.name}: arrays need `of:` (a type or a schema)"
          end
        end
        errors.size == before ? items.freeze : INVALID
      end

      def check_constraints(field, value, path, errors, item: false)
        opts = field.options
        enum = opts[:enum]
        if enum && !enum.map(&:to_s).include?(value.to_s)
          add_error(errors, path, "must be one of: #{enum.join(', ')}")
          return INVALID
        end

        if value.is_a?(String)
          max = opts[:max_length] || Types::DEFAULT_MAX_STRING
          add_error(errors, path, "must be at most #{max} characters") if value.length > max
          add_error(errors, path, "must be at least #{opts[:min_length]} characters") if opts[:min_length] && value.length < opts[:min_length]
          add_error(errors, path, "has an invalid format") if opts[:format] && !value.match?(opts[:format])
        elsif value.is_a?(Numeric)
          add_error(errors, path, "must be at least #{opts[:min]}") if opts[:min] && value < opts[:min]
          add_error(errors, path, "must be at most #{opts[:max]}") if opts[:max] && value > opts[:max]
          if opts[:scale] && value.is_a?(BigDecimal) && value.round(opts[:scale]) != value
            add_error(errors, path, "must have at most #{opts[:scale]} decimal places")
          end
        end
        _ = item
        value
      end

      # ---- output ----------------------------------------------------------

      # Serializes an object (or Hash) into a Hash with only the declared
      # fields. Reads attributes with public_send, or `from:` (a method name
      # or ->(object) { ... }).
      def dump(object)
        return nil if object.nil?

        fields.each_value.with_object({}) do |field, out|
          out[field.key] = dump_value(field, read(object, field))
        end
      end

      def dump_many(objects)
        objects.map { |o| dump(o) }
      end

      def read(object, field)
        source = field.options[:from] || field.name
        return source.call(object) if source.respond_to?(:call)

        if object.is_a?(Hash)
          object.fetch(source.to_s) { object[source.to_sym] }
        elsif object.respond_to?(source)
          object.public_send(source)
        end
      end

      def dump_value(field, value)
        return nil if value.nil?

        case field.type
        when :object then field.schema ? field.schema.dump(value) : Types.plain(value)
        when :array
          list = value.respond_to?(:to_a) ? value.to_a : Array(value)
          if field.item_schema? then list.map { |v| field.item_type.dump(v) }
          else list.map { |v| Types.dump(field.item_type&.to_sym || :json, v, field.options[:scale]) }
          end
        when :decimal then Types.dump(:decimal, value, field.options[:scale])
        else Types.dump(field.type, value)
        end
      end

      # ---- OpenAPI ---------------------------------------------------------

      def to_json_schema(ref: nil)
        properties = {}
        required = []
        fields.each_value do |field|
          properties[field.key] = field_json_schema(field, ref)
          required << field.key if field.required?
        end
        schema = { "type" => "object", "properties" => properties }
        schema["required"] = required unless required.empty?
        schema["additionalProperties"] = false if reject_unknown?
        schema
      end

      private

      def field_json_schema(field, ref)
        schema =
          case field.type
          when :object
            field.schema ? schema_ref(field.schema, ref) : { "type" => "object" }
          when :array
            items = if field.item_schema? then schema_ref(field.item_type, ref)
                    elsif field.item_type then scalar_json_schema(field.item_type.to_sym)
                    else {}
                    end
            { "type" => "array", "items" => items, "maxItems" => field.options.fetch(:max_items, DEFAULT_MAX_ITEMS) }
          else
            scalar_json_schema(field.type)
          end
        o = field.options
        schema = schema.merge("enum" => o[:enum].map(&:to_s)) if o[:enum]
        schema["minimum"] = o[:min] if o[:min]
        schema["maximum"] = o[:max] if o[:max]
        schema["minLength"] = o[:min_length] if o[:min_length]
        schema["maxLength"] = o[:max_length] if o[:max_length]
        schema["minItems"] = o[:min_items] if o[:min_items]
        schema["description"] = o[:description] if o[:description]
        schema["example"] = o[:example] if o.key?(:example)
        schema["deprecated"] = true if o[:deprecated]
        schema["default"] = o[:default] if o.key?(:default) && !o[:default].respond_to?(:call)
        schema = { "anyOf" => [schema, { "type" => "null" }] } if field.nullable? && schema.key?("$ref")
        schema["type"] = [schema["type"], "null"] if field.nullable? && schema["type"].is_a?(String)
        schema
      end

      def schema_ref(schema, ref)
        ref ? ref.call(schema) : schema.to_json_schema
      end

      def scalar_json_schema(type)
        case type
        when :string, :text then { "type" => "string" }
        when :integer then { "type" => "integer" }
        when :float then { "type" => "number" }
        when :decimal then { "type" => "string", "format" => "decimal" }
        when :boolean then { "type" => "boolean" }
        when :date then { "type" => "string", "format" => "date" }
        when :datetime, :time then { "type" => "string", "format" => "date-time" }
        when :uuid then { "type" => "string", "format" => "uuid" }
        when :email then { "type" => "string", "format" => "email" }
        when :url then { "type" => "string", "format" => "uri" }
        else {}
        end
      end

      def validate_type!(name, type, options)
        return if type.is_a?(Class) && type <= Schema

        sym = type.to_sym
        unless Types::NAMES.include?(sym)
          raise DefinitionError, "#{schema_name || 'Schema'}.#{name}: unknown type #{type.inspect}. " \
                                 "Use one of #{Types::NAMES.join(', ')} or a Whoosh::Schema subclass"
        end
        if options.key?(:scale)
          decimal = sym == :decimal || (sym == :array && options[:of].to_s == "decimal")
          unless decimal && options[:scale].is_a?(Integer) && options[:scale] >= 0
            raise DefinitionError, "#{schema_name || 'Schema'}.#{name}: `scale:` takes a whole number, on decimals only"
          end
        end
        if sym == :array && options[:of].nil?
          raise DefinitionError, "#{schema_name || 'Schema'}.#{name}: arrays need `of:` (a type or a schema)"
        end
        if sym == :object && options[:schema].nil?
          raise DefinitionError, "#{schema_name || 'Schema'}.#{name}: give objects a schema (a block or a Schema class), " \
                                 "or use :json for free-form data"
        end
      end

      def join(path, key) = path.empty? ? key.to_s : "#{path}.#{key}"

      def add_error(errors, path, message)
        (errors[path.empty? ? "base" : path] ||= []) << message
      end
    end
  end
end
