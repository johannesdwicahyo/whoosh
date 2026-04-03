# spec/whoosh/client_gen/integration_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh"
require "whoosh/client_gen/introspector"
require "whoosh/client_gen/fallback_backend"

RSpec.describe "Client Generator Integration" do
  describe "full introspection round-trip" do
    it "introspects a Whoosh app with auth and CRUD routes" do
      app = Whoosh::App.new
      app.auth { jwt secret: "test-secret-key-for-testing", algorithm: :hs256, expiry: 3600 }

      task_request = Class.new(Whoosh::Schema) do
        field :title, String, required: true, desc: "Task title"
        field :description, String, desc: "Description"
        field :status, String, enum: %w[pending in_progress done], default: "pending", desc: "Status"
      end

      app.post "/auth/login" do |req|
        { token: "test" }
      end

      app.post "/auth/register" do |req|
        { token: "test" }
      end

      app.get "/tasks", auth: :jwt do |req|
        { items: [], cursor: nil }
      end

      app.get "/tasks/:id", auth: :jwt do |req|
        { id: 1, title: "Test" }
      end

      app.post "/tasks", auth: :jwt, request: task_request do |req|
        { id: 1, title: req.body[:title] }
      end

      app.put "/tasks/:id", auth: :jwt, request: task_request do |req|
        { id: 1, title: req.body[:title] }
      end

      app.delete "/tasks/:id", auth: :jwt do |req|
        { deleted: true }
      end

      introspector = Whoosh::ClientGen::Introspector.new(app)
      ir = introspector.introspect

      expect(ir.auth.type).to eq(:jwt)
      expect(ir.auth.endpoints).to have_key(:login)
      expect(ir.auth.endpoints).to have_key(:register)
      expect(ir.resources.length).to eq(1)

      tasks = ir.resources.first
      expect(tasks.name).to eq(:tasks)
      expect(tasks.crud_actions).to match_array([:index, :show, :create, :update, :destroy])
      expect(tasks.fields.length).to eq(3)
      expect(tasks.fields.find { |f| f[:name] == :title }[:type]).to eq(:string)
    end
  end

  describe "fallback backend generation" do
    it "generates a complete backend that could be introspected" do
      Dir.mktmpdir do |dir|
        Whoosh::ClientGen::FallbackBackend.generate(root: dir, oauth: false)

        %w[
          endpoints/auth_endpoint.rb
          endpoints/tasks_endpoint.rb
          schemas/auth_schemas.rb
          schemas/task_schemas.rb
        ].each do |path|
          expect(File.exist?(File.join(dir, path))).to be(true), "Missing: #{path}"
        end

        migrations = Dir.glob(File.join(dir, "db/migrations/*.rb"))
        expect(migrations.length).to eq(2)
      end
    end
  end
end
