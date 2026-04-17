# spec/whoosh/app_endpoints_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "tmpdir"

RSpec.describe "App endpoint loading" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "#register_endpoint" do
    it "registers all declared routes from an endpoint class" do
      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/items"
        post "/items"

        def call(req)
          { method: req.method }
        end
      end

      application.register_endpoint(endpoint_class)

      get "/items"
      expect(JSON.parse(last_response.body)["method"]).to eq("GET")

      post "/items"
      expect(JSON.parse(last_response.body)["method"]).to eq("POST")
    end
  end

  describe "endpoint with context delegation" do
    it "delegates method calls to app via Context" do
      application.provide(:greeter) { "Hello" }

      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/greet"

        def call(req)
          { greeting: "works" }
        end
      end

      application.register_endpoint(endpoint_class)
      get "/greet"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["greeting"]).to eq("works")
    end
  end

  describe "endpoint with inject DSL" do
    it "resolves and exposes injected dependencies as accessors" do
      application.provide(:greeter) { "Hi" }
      application.provide(:suffix) { "!" }

      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/hello"
        inject :greeter, :suffix

        def call(_req)
          { message: "#{greeter}, world#{suffix}" }
        end
      end

      application.register_endpoint(endpoint_class)
      get "/hello"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["message"]).to eq("Hi, world!")
    end

    it "passes the current request to request-scoped providers" do
      application.provide(:current_path, scope: :request) { |req| req.path }

      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/where"
        inject :current_path

        def call(_req)
          { path: current_path }
        end
      end

      application.register_endpoint(endpoint_class)
      get "/where"
      expect(JSON.parse(last_response.body)["path"]).to eq("/where")
    end

    it "raises a clear error when injecting an unknown dependency" do
      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/nope"
        inject :not_registered

        def call(_req)
          { ok: true }
        end
      end

      application.register_endpoint(endpoint_class)
      get "/nope"
      expect(last_response.status).to eq(500)
    end
  end
end
