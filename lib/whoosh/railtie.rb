module Whoosh
  class Railtie < ::Rails::Railtie
    initializer "whoosh.defaults" do
      Whoosh.config.logger ||= Rails.logger
      Whoosh.config.expose_errors = true if Rails.env.development?
    end

    config.after_initialize do
      # Share rate limits and idempotency keys across Puma workers and hosts.
      if Whoosh.config.store.is_a?(Whoosh::Stores::Memory) && !Rails.env.test? && Rails.cache
        Whoosh.config.store = Whoosh::Stores::Cache.new(Rails.cache)
      end
    end

    # In tests, rate limits, idempotency keys and api_sign_in must not carry over
    # from one example to the next. Covers RSpec and ActiveSupport::TestCase.
    config.after_initialize do
      if Rails.env.test?
        require "whoosh/test_helpers"
        if defined?(RSpec) && RSpec.respond_to?(:configure)
          RSpec.configure do |c|
            c.before(:each) { Whoosh::TestHelpers.reset! }
            c.include Whoosh::TestHelpers, type: :request
          end
        end
        ActiveSupport.on_load(:active_support_test_case) { setup { Whoosh::TestHelpers.reset! } }
        ActiveSupport.on_load(:action_dispatch_integration_test) { include Whoosh::TestHelpers }
      end
    end

    generators do
      require "generators/whoosh/install/install_generator"
      require "generators/whoosh/api/api_generator"
    end
  end
end
