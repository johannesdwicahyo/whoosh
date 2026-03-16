# frozen_string_literal: true

module Whoosh
  module Middleware
    class PluginHooks
      def initialize(app, plugins:, configs:)
        @app = app
        @plugins = plugins.select { |p| p.respond_to?(:middleware?) && p.middleware? }
        @configs = configs
      end

      def call(env)
        @plugins.each do |plugin|
          plugin.before_request(env, @configs[plugin] || {}) if plugin.respond_to?(:before_request)
        end

        status, headers, body = @app.call(env)

        @plugins.each do |plugin|
          plugin.after_response([status, headers, body], @configs[plugin] || {}) if plugin.respond_to?(:after_response)
        end

        [status, headers, body]
      end
    end
  end
end
