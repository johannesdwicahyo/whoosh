# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::Stack do
  let(:inner_app) { ->(env) { [200, { "content-type" => "text/plain" }, ["OK"]] } }

  describe "#use" do
    it "adds middleware to the stack" do
      stack = Whoosh::Middleware::Stack.new
      test_middleware = Class.new do
        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, body = @app.call(env)
          headers["x-test"] = "true"
          [status, headers, body]
        end
      end

      stack.use(test_middleware)
      app = stack.build(inner_app)

      env = Rack::MockRequest.env_for("/test")
      status, headers, = app.call(env)

      expect(status).to eq(200)
      expect(headers["x-test"]).to eq("true")
    end
  end

  describe "#build" do
    it "wraps the app with middleware in order" do
      stack = Whoosh::Middleware::Stack.new
      app = stack.build(inner_app)

      env = Rack::MockRequest.env_for("/test")
      status, _, body = app.call(env)
      expect(status).to eq(200)
      expect(body).to eq(["OK"])
    end
  end
end
