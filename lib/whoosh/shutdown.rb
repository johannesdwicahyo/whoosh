# frozen_string_literal: true

module Whoosh
  class Shutdown
    def initialize(logger: nil)
      @hooks = []
      @logger = logger
      @executed = false
    end

    def register(&block)
      @hooks << block
    end

    def execute!
      return if @executed
      @executed = true
      @hooks.reverse_each do |hook|
        hook.call
      rescue => e
        @logger&.error("shutdown_hook_error", message: e.message)
      end
    end

    def install_signal_handlers!
      trap("TERM") { execute! }
      trap("INT") { execute! }
    end
  end
end
