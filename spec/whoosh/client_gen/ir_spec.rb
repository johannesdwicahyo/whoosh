# frozen_string_literal: true

require "spec_helper"
require "whoosh/client_gen/ir"

RSpec.describe Whoosh::ClientGen::IR do
  describe Whoosh::ClientGen::IR::Schema do
    it "builds from fields hash" do
      schema = Whoosh::ClientGen::IR::Schema.new(
        name: :task,
        fields: [
          { name: :title, type: :string, required: true },
          { name: :status, type: :string, required: false, enum: %w[pending done], default: "pending" }
        ]
      )
      expect(schema.name).to eq(:task)
      expect(schema.fields.length).to eq(2)
      expect(schema.fields.first[:required]).to be true
      expect(schema.fields.last[:enum]).to eq(%w[pending done])
    end
  end

  describe Whoosh::ClientGen::IR::Endpoint do
    it "stores method, path, action, and schemas" do
      ep = Whoosh::ClientGen::IR::Endpoint.new(
        method: :get, path: "/tasks", action: :index,
        request_schema: nil, response_schema: :task, pagination: true
      )
      expect(ep.method).to eq(:get)
      expect(ep.action).to eq(:index)
      expect(ep.pagination).to be true
    end
  end

  describe Whoosh::ClientGen::IR::Resource do
    it "groups endpoints under a resource name" do
      resource = Whoosh::ClientGen::IR::Resource.new(
        name: :tasks,
        endpoints: [
          Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index),
          Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create)
        ],
        fields: [{ name: :title, type: :string, required: true }]
      )
      expect(resource.name).to eq(:tasks)
      expect(resource.endpoints.length).to eq(2)
      expect(resource.crud_actions).to include(:index, :create)
    end
  end

  describe Whoosh::ClientGen::IR::Auth do
    it "stores auth type and endpoints" do
      auth = Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          refresh: { method: :post, path: "/auth/refresh" },
          logout: { method: :delete, path: "/auth/logout" }
        },
        oauth_providers: []
      )
      expect(auth.type).to eq(:jwt)
      expect(auth.endpoints.keys).to include(:login, :register)
      expect(auth.oauth_providers).to be_empty
    end
  end

  describe Whoosh::ClientGen::IR::AppSpec do
    it "holds complete app IR" do
      app_spec = Whoosh::ClientGen::IR::AppSpec.new(
        auth: Whoosh::ClientGen::IR::Auth.new(type: :jwt, endpoints: {}, oauth_providers: []),
        resources: [],
        streaming: [],
        base_url: "http://localhost:9292"
      )
      expect(app_spec.base_url).to eq("http://localhost:9292")
      expect(app_spec.auth.type).to eq(:jwt)
      expect(app_spec.resources).to be_empty
    end

    it "reports whether it has resources" do
      app_spec = Whoosh::ClientGen::IR::AppSpec.new(
        auth: nil, resources: [], streaming: [], base_url: "http://localhost:9292"
      )
      expect(app_spec.has_resources?).to be false
      expect(app_spec.has_auth?).to be false
    end
  end
end
