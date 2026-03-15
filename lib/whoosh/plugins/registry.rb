# frozen_string_literal: true

require "set"

module Whoosh
  module Plugins
    class Registry
      # Default mappings: gem name => accessor symbol
      DEFAULT_GEMS = {
        "ruby_llm"        => :llm,
        "lingua-ruby"     => :lingua,
        "keyword-ruby"    => :keyword,
        "ner-ruby"        => :ner,
        "loader-ruby"     => :loader,
        "prompter-ruby"   => :prompter,
        "chunker-ruby"    => :chunker,
        "guardrails-ruby" => :guardrails,
        "rag-ruby"        => :rag,
        "eval-ruby"       => :eval_,
        "connector-ruby"  => :connector,
        "sastrawi-ruby"   => :sastrawi,
        "pattern-ruby"    => :pattern,
        "onnx-ruby"       => :onnx,
        "tokenizer-ruby"  => :tokenizer,
        "zvec-ruby"       => :zvec,
        "reranker-ruby"   => :reranker,
        "sequel"          => :db
      }.freeze

      def initialize
        @gems = {}
        @configs = {}
        @disabled = Set.new
        @mutex = Mutex.new

        register_defaults
      end

      def register(gem_name, accessor:, initializer: nil)
        @gems[gem_name] = { accessor: accessor, initializer: initializer }
      end

      def registered?(gem_name)
        @gems.key?(gem_name)
      end

      def accessor_for(gem_name)
        @gems.dig(gem_name, :accessor)
      end

      def scan_gemfile_lock(content)
        specs_section = false
        detected = []

        content.each_line do |line|
          stripped = line.strip
          if stripped == "specs:"
            specs_section = true
            next
          end

          if specs_section
            break if stripped.empty? || !line.start_with?("  ")

            # Lines like "    lingua-ruby (0.1.0)"
            match = stripped.match(/\A(\S+)\s+\(/)
            if match && @gems.key?(match[1])
              detected << match[1]
            end
          end
        end

        detected
      end

      def define_accessors(target)
        @gems.each do |gem_name, entry|
          accessor = entry[:accessor]
          next if @disabled.include?(accessor)

          initializer = entry[:initializer]
          config = @configs[accessor] || {}
          mutex = @mutex
          instance_var = :"@_plugin_#{accessor}"

          target.define_singleton_method(accessor) do
            cached = instance_variable_get(instance_var)
            return cached if cached

            mutex.synchronize do
              # Double-check inside lock
              cached = instance_variable_get(instance_var)
              return cached if cached

              instance = if initializer
                initializer.call(config)
              else
                begin
                  require gem_name.tr("-", "/")
                rescue LoadError
                  raise Whoosh::Errors::DependencyError,
                    "Plugin '#{accessor}' requires gem '#{gem_name}' but it could not be loaded"
                end
                nil
              end

              instance_variable_set(instance_var, instance || true)
              instance
            end
          end
        end
      end

      def configure(accessor, config)
        @configs[accessor] = config
      end

      def config_for(accessor)
        @configs[accessor]
      end

      def disable(accessor)
        @disabled.add(accessor)
      end

      def disabled?(accessor)
        @disabled.include?(accessor)
      end

      private

      def register_defaults
        DEFAULT_GEMS.each do |gem_name, accessor|
          register(gem_name, accessor: accessor)
        end
      end
    end
  end
end
