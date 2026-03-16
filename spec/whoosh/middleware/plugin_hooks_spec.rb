# spec/whoosh/middleware/plugin_hooks_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::PluginHooks do
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }

  it "calls before_request on middleware plugins" do
    calls = []
    plugin = Class.new(Whoosh::Plugins::Base) do
      define_singleton_method(:middleware?) { true }
      define_singleton_method(:before_request) { |req, config| calls << :before }
    end
    app = Whoosh::Middleware::PluginHooks.new(inner_app, plugins: [plugin], configs: {})
    app.call(Rack::MockRequest.env_for("/test"))
    expect(calls).to eq([:before])
  end

  it "calls after_response on middleware plugins" do
    calls = []
    plugin = Class.new(Whoosh::Plugins::Base) do
      define_singleton_method(:middleware?) { true }
      define_singleton_method(:after_response) { |res, config| calls << :after }
    end
    app = Whoosh::Middleware::PluginHooks.new(inner_app, plugins: [plugin], configs: {})
    app.call(Rack::MockRequest.env_for("/test"))
    expect(calls).to eq([:after])
  end

  it "passes through when no middleware plugins" do
    app = Whoosh::Middleware::PluginHooks.new(inner_app, plugins: [], configs: {})
    status, _, body = app.call(Rack::MockRequest.env_for("/test"))
    expect(status).to eq(200)
  end
end
