# lib/whoosh/client_gen/base_generator.rb
# frozen_string_literal: true

require "fileutils"
require "whoosh/client_gen/ir"

module Whoosh
  module ClientGen
    class BaseGenerator
      TYPE_MAPS = {
        typescript: {
          string: "string", integer: "number", number: "number",
          boolean: "boolean", array: "any[]", object: "Record<string, any>"
        },
        swift: {
          string: "String", integer: "Int", number: "Double",
          boolean: "Bool", array: "[Any]", object: "[String: Any]"
        },
        dart: {
          string: "String", integer: "int", number: "double",
          boolean: "bool", array: "List<dynamic>", object: "Map<String, dynamic>"
        },
        ruby: {
          string: "String", integer: "Integer", number: "Float",
          boolean: "Boolean", array: "Array", object: "Hash"
        },
        html: {
          string: "text", integer: "number", number: "number",
          boolean: "checkbox", array: "text", object: "text"
        }
      }.freeze

      attr_reader :ir, :output_dir, :platform

      def initialize(ir:, output_dir:, platform:)
        @ir = ir
        @output_dir = output_dir
        @platform = platform
      end

      def generate
        raise NotImplementedError, "Subclasses must implement #generate"
      end

      def type_for(ir_type)
        TYPE_MAPS.dig(@platform, ir_type.to_sym) || "string"
      end

      def write_file(relative_path, content)
        full_path = File.join(@output_dir, relative_path)
        FileUtils.mkdir_p(File.dirname(full_path))
        File.write(full_path, content)
      end

      def classify(name)
        singular = singularize(name.to_s)
        singular.split(/[-_]/).map(&:capitalize).join
      end

      def singularize(word)
        w = word.to_s
        if w.end_with?("ies")
          w[0..-4] + "y"
        elsif w.end_with?("ses") || w.end_with?("xes") || w.end_with?("zes") || w.end_with?("ches") || w.end_with?("shes")
          w[0..-3]
        elsif w.end_with?("sses")
          w[0..-3]
        elsif w.end_with?("s") && !w.end_with?("ss") && !w.end_with?("us")
          w[0..-2]
        else
          w
        end
      end

      def camelize(name)
        name.to_s.split(/[-_]/).map(&:capitalize).join
      end

      def snake_case(name)
        name.to_s.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, "")
      end
    end
  end
end
