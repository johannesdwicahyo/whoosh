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

    # In tests, rate limits and idempotency keys must not carry over from one
    # example to the next. Covers RSpec and ActiveSupport::TestCase.
    config.after_initialize do
      if Rails.env.test?
        reset = -> { Whoosh.config.store.clear if Whoosh.config.store.respond_to?(:clear) }
        RSpec.configure { |c| c.before(:each) { reset.call } } if defined?(RSpec) && RSpec.respond_to?(:configure)
        ActiveSupport.on_load(:active_support_test_case) { setup { reset.call } }
      end
    end

    generators do
      require "generators/whoosh/install/install_generator"
    end
  end
end
