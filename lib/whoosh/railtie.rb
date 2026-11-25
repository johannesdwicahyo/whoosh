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

    generators do
      require "generators/whoosh/install/install_generator"
    end
  end
end
