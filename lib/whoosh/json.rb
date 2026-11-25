module Whoosh
  # JSON encoding and decoding. Uses Oj when the app has it loaded; falls back
  # to the stdlib json gem. Parsing never creates arbitrary objects.
  module JSON
    module_function

    def dump(value)
      if defined?(::Oj)
        ::Oj.dump(value, mode: :compat)
      else
        ::JSON.generate(value)
      end
    end

    def parse(string, max_depth:)
      ::JSON.parse(string, max_nesting: max_depth, allow_nan: false)
    rescue ::JSON::NestingError
      raise BadRequest.new("The JSON body is nested too deeply.")
    rescue ::JSON::ParserError
      raise BadRequest.new("The JSON body is malformed.")
    end

    # Counts keys and array items so a small body can't expand into a huge
    # structure. Raises when over the limit.
    def check_size!(value, max_keys)
      count = 0
      stack = [value]
      until stack.empty?
        current = stack.pop
        case current
        when Hash
          count += current.size
          stack.concat(current.values)
        when Array
          count += current.size
          stack.concat(current)
        end
        raise BadRequest.new("The JSON body has too many keys or items.") if count > max_keys
      end
      value
    end
  end
end
