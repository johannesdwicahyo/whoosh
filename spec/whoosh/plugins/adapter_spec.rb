# spec/whoosh/plugins/adapter_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "Plugin adapter integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "full plugin lifecycle" do
    before do
      application.plugin_registry.register("mock-lingua",
        accessor: :lingua,
        initializer: -> (config) {
          obj = Object.new
          langs = config[:languages] || config["languages"] || ["en"]
          obj.define_singleton_method(:detect) { |text| langs.first }
          obj
        }
      )
      application.plugin_registry.register("mock-ner",
        accessor: :ner,
        initializer: -> (config) {
          obj = Object.new
          obj.define_singleton_method(:recognize) { |text| [{ entity: "test", text: text[0..10] }] }
          obj
        }
      )
      application.plugin_registry.register("mock-llm",
        accessor: :llm,
        initializer: -> (config) {
          obj = Object.new
          obj.define_singleton_method(:complete) { |prompt| "Response to: #{prompt}" }
          obj
        }
      )
      application.plugin :lingua, languages: ["en", "id"]
      application.setup_plugin_accessors

      application.post "/analyze" do |req|
        text = req.body["text"]
        {
          language: lingua.detect(text),
          entities: ner.recognize(text),
          response: llm.complete(text)
        }
      end
    end

    it "makes all plugins available in endpoints" do
      post "/analyze", { text: "Hello world" }.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["language"]).to eq("en")
      expect(body["entities"]).to be_an(Array)
      expect(body["response"]).to include("Hello world")
    end

    it "passes config to plugin initializer" do
      post "/analyze", { text: "test" }.to_json, "CONTENT_TYPE" => "application/json"
      body = JSON.parse(last_response.body)
      expect(body["language"]).to eq("en")
    end
  end

  describe "disabled plugins" do
    it "does not define accessor for disabled plugins" do
      application.plugin_registry.register("mock-disabled",
        accessor: :disabled_thing,
        initializer: -> (config) { "should not load" }
      )
      application.plugin :disabled_thing, enabled: false
      application.setup_plugin_accessors
      expect(application).not_to respond_to(:disabled_thing)
    end
  end

  describe "plugin override" do
    it "allows overriding a plugin" do
      application.plugin_registry.register("v1",
        accessor: :tool,
        initializer: -> (config) { "v1" }
      )
      application.plugin_registry.register("v2",
        accessor: :tool,
        initializer: -> (config) { "v2" }
      )
      application.setup_plugin_accessors

      application.get "/tool" do
        { version: tool }
      end

      get "/tool"
      expect(JSON.parse(last_response.body)["version"]).to eq("v2")
    end
  end
end
