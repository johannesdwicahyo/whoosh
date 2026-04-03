# frozen_string_literal: true

require "spec_helper"
require "whoosh"
require "whoosh/client_gen/introspector"

RSpec.describe Whoosh::ClientGen::Introspector do
  def build_test_app
    app = Whoosh::App.new
    app.auth { jwt secret: "test-secret", algorithm: :hs256, expiry: 3600 }

    app.post "/auth/login" do |req|
      { token: "fake" }
    end

    app.post "/auth/register" do |req|
      { token: "fake" }
    end

    app.get "/tasks", auth: :jwt do |req|
      { items: [] }
    end

    app.get "/tasks/:id", auth: :jwt do |req|
      { id: req.params[:id] }
    end

    app.post "/tasks", auth: :jwt do |req|
      { id: 1 }
    end

    app.put "/tasks/:id", auth: :jwt do |req|
      { updated: true }
    end

    app.delete "/tasks/:id", auth: :jwt do |req|
      { deleted: true }
    end

    app
  end

  describe "#introspect" do
    it "returns an AppSpec IR from a Whoosh app" do
      app = build_test_app
      introspector = described_class.new(app)
      ir = introspector.introspect

      expect(ir).to be_a(Whoosh::ClientGen::IR::AppSpec)
      expect(ir.base_url).to eq("http://localhost:9292")
    end

    it "detects JWT auth and auth endpoints" do
      app = build_test_app
      ir = described_class.new(app).introspect

      expect(ir.auth).not_to be_nil
      expect(ir.auth.type).to eq(:jwt)
      expect(ir.auth.endpoints).to have_key(:login)
      expect(ir.auth.endpoints).to have_key(:register)
    end

    it "groups CRUD routes into resources" do
      app = build_test_app
      ir = described_class.new(app).introspect

      expect(ir.resources.length).to eq(1)
      tasks = ir.resources.first
      expect(tasks.name).to eq(:tasks)
      expect(tasks.crud_actions).to include(:index, :show, :create, :update, :destroy)
    end
  end

  describe "#introspect with schemas" do
    it "extracts field types from request schemas" do
      app = Whoosh::App.new

      task_schema = Class.new(Whoosh::Schema) do
        field :title, String, required: true, desc: "Task title"
        field :status, String, required: false, desc: "Status"
      end

      app.post "/tasks", request: task_schema do |req|
        { id: 1 }
      end

      ir = described_class.new(app).introspect
      resource = ir.resources.first
      expect(resource.fields.length).to eq(2)
      expect(resource.fields.first[:name]).to eq(:title)
      expect(resource.fields.first[:type]).to eq(:string)
      expect(resource.fields.first[:required]).to be true
    end
  end

  describe "#introspect with no routes" do
    it "returns empty IR" do
      app = Whoosh::App.new
      ir = described_class.new(app).introspect

      expect(ir.has_auth?).to be false
      expect(ir.has_resources?).to be false
    end
  end
end
