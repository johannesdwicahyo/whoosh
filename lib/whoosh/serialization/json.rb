# lib/whoosh/serialization/json.rb
# frozen_string_literal: true

require "json"
require "bigdecimal"

module Whoosh
  module Serialization
    class Json
      @engine = nil
      @oj_available = nil

      class << self
        attr_reader :engine

        def detect_engine!
          @oj_available = begin
            require "oj"
            true
          rescue LoadError
            false
          end
          @engine = @oj_available ? :oj : :json
        end

        def use_engine(name)
          @engine = name.to_sym
        end

        def encode(data)
          detect_engine! unless @engine
          prepared = prepare(data)

          if @engine == :oj
            Oj.dump(prepared, mode: :compat)
          else
            JSON.generate(prepared)
          end
        end

        def decode(raw)
          return nil if raw.nil? || raw.empty?
          detect_engine! unless @engine

          if @engine == :oj
            Oj.load(raw, mode: :compat)
          else
            JSON.parse(raw)
          end
        end

        def content_type
          "application/json"
        end

        def prepare(obj)
          case obj
          when Hash
            obj.transform_values { |v| prepare(v) }
          when Array
            obj.map { |v| prepare(v) }
          when Time, DateTime
            obj.iso8601
          when BigDecimal
            obj.to_s("F")
          else
            obj
          end
        end
      end
    end
  end
end
