module Whoosh
  # Helpers for request specs and integration tests. In Rails they are included
  # for you; elsewhere `require "whoosh/test_helpers"` and include the module.
  module TestHelpers
    # Make every API request in this test as `user`, with no token or header.
    # Pass nil to become signed out again.
    # ponytail: swaps one process-wide setting, so it is wrong for tests run in parallel threads
    # (parallel processes are fine). Give it a per-thread user if someone needs that.
    def api_sign_in(user)
      TestHelpers.saved ||= [Whoosh.config.authenticate]
      Whoosh.config.authenticate = ->(_request) { user }
    end

    class << self
      attr_accessor :saved

      # Call before each test: forgets rate limits and idempotency keys, and undoes api_sign_in.
      def reset!
        store = Whoosh.config.store
        store.clear if store.respond_to?(:clear)
        return unless saved

        Whoosh.config.authenticate = saved.first
        self.saved = nil
      end
    end
  end
end
