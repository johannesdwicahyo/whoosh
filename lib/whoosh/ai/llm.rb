# frozen_string_literal: true

module Whoosh
  module AI
    # Bounded LRU cache. Ruby's Hash preserves insertion order, so we reorder
    # on read (delete+reinsert) and evict the oldest entry when over capacity.
    class LRUCache
      def initialize(max_size)
        @max_size = max_size
        @store = {}
        @mutex = Mutex.new
      end

      def [](key)
        @mutex.synchronize do
          return nil unless @store.key?(key)
          value = @store.delete(key)
          @store[key] = value
        end
      end

      def []=(key, value)
        @mutex.synchronize do
          @store.delete(key) if @store.key?(key)
          @store[key] = value
          @store.shift while @store.size > @max_size
          value
        end
      end

      def size
        @store.size
      end
    end

    DEFAULT_MODEL     = "claude-sonnet-4-6"
    DEFAULT_CACHE_MAX = 1000

    class LLM
      attr_reader :provider, :model

      def initialize(provider: "auto", model: nil, cache_enabled: true, cache_size: DEFAULT_CACHE_MAX)
        @provider = provider
        @model = model
        @cache_enabled = cache_enabled
        @cache = cache_enabled ? LRUCache.new(cache_size) : nil
        @ruby_llm = nil
      end

      # Chat with an LLM — returns response text
      def chat(message, model: nil, system: nil, max_tokens: nil, temperature: nil, cache: nil)
        use_cache = cache.nil? ? @cache_enabled : cache
        cache_key = "chat:#{model || @model}:#{message}" if use_cache

        # Check cache
        if use_cache && @cache && (cached = @cache[cache_key])
          return cached
        end

        result = call_llm(
          messages: [{ role: "user", content: message }],
          model: model || @model,
          system: system,
          max_tokens: max_tokens,
          temperature: temperature
        )

        @cache[cache_key] = result if use_cache && @cache

        result
      end

      # Extract structured data — returns validated hash
      def extract(text, schema:, model: nil, prompt: nil)
        schema_desc = describe_schema(schema)
        system_prompt = prompt || "Extract structured data from the text. Return ONLY valid JSON matching this schema:\n#{schema_desc}"

        response = chat(text, model: model, system: system_prompt, cache: false)

        # Parse JSON from LLM response
        json_str = extract_json(response)
        parsed = Serialization::Json.decode(json_str)

        # Validate against schema
        result = schema.validate(parsed)
        if result.success?
          result.data
        else
          raise Errors::ValidationError.new(result.errors)
        end
      end

      # Stream LLM response — yields chunks
      def stream(message, model: nil, system: nil, &block)
        ensure_ruby_llm!

        messages = [{ role: "user", content: message }]
        # Delegate to ruby_llm's streaming interface
        if @ruby_llm
          # ruby_llm streaming would go here
          # For now, fall back to non-streaming
          result = chat(message, model: model, system: system, cache: false)
          yield result if block_given?
          result
        end
      end

      # Check if LLM is available
      def available?
        ruby_llm_available?
      end

      private

      def call_llm(messages:, model:, system: nil, max_tokens: nil, temperature: nil)
        ensure_ruby_llm!

        if @ruby_llm
          # Use ruby_llm gem
          chat = RubyLLM.chat(model: model || DEFAULT_MODEL)
          chat.with_instructions(system) if system
          response = chat.ask(messages.last[:content])
          response.content
        else
          raise Errors::DependencyError, "No LLM provider available. Add 'ruby_llm' to your Gemfile."
        end
      end

      def ensure_ruby_llm!
        return if @ruby_llm == false # already checked, not available

        if ruby_llm_available?
          @ruby_llm = true
        else
          @ruby_llm = false
        end
      end

      def ruby_llm_available?
        require "ruby_llm"
        true
      rescue LoadError
        false
      end

      def describe_schema(schema)
        return "{}" unless schema.respond_to?(:fields)
        fields = schema.fields.map do |name, opts|
          type = OpenAPI::SchemaConverter.type_for(opts[:type])
          desc = opts[:desc] ? " — #{opts[:desc]}" : ""
          required = opts[:required] ? " (required)" : ""
          "  #{name}: #{type}#{required}#{desc}"
        end
        "{\n#{fields.join(",\n")}\n}"
      end

      def extract_json(text)
        # Try to find JSON in LLM response (may be wrapped in markdown code blocks)
        if text =~ /```(?:json)?\s*\n?(.*?)\n?```/m
          $1.strip
        elsif text.strip.start_with?("{") || text.strip.start_with?("[")
          text.strip
        else
          text.strip
        end
      end
    end
  end
end
