# frozen_string_literal: true

module Whoosh
  module VectorStore
    autoload :MemoryStore, "whoosh/vector_store/memory_store"

    # Auto-detect: zvec gem → use it, otherwise → in-memory
    def self.build(config_data = {})
      vector_config = config_data["vector"] || {}
      adapter = vector_config["adapter"] || "auto"

      case adapter
      when "auto"
        # Try zvec first, fall back to memory
        if zvec_available?
          require "whoosh/vector_store/zvec_store"
          ZvecStore.new(**zvec_options(vector_config))
        else
          MemoryStore.new
        end
      when "memory"
        MemoryStore.new
      when "zvec"
        require "whoosh/vector_store/zvec_store"
        ZvecStore.new(**zvec_options(vector_config))
      else
        MemoryStore.new
      end
    end

    def self.zvec_available?
      require "zvec"
      true
    rescue LoadError
      false
    end

    def self.zvec_options(config)
      { path: config["path"] || "db/vectors" }
    end
  end
end
