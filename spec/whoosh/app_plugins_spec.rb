# spec/whoosh/app_plugins_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App plugin integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "#plugin" do
    it "configures a registered plugin" do
      application.plugin :lingua, languages: [:en, :id]
      expect(application.plugin_registry.config_for(:lingua)).to eq({ languages: [:en, :id] })
    end

    it "disables a plugin with enabled: false" do
      application.plugin :ner, enabled: false
      expect(application.plugin_registry.disabled?(:ner)).to be true
    end
  end

  describe "plugin accessor via endpoint" do
    it "makes plugin accessors available in inline endpoints" do
      # Register a test plugin with a known initializer
      application.plugin_registry.register("test-plugin",
        accessor: :test_tool,
        initializer: -> (_config) { "tool_instance" }
      )
      application.setup_plugin_accessors

      application.get "/use-plugin" do
        { tool: test_tool }
      end

      get "/use-plugin"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["tool"]).to eq("tool_instance")
    end
  end
end
