# spec/whoosh/client_gen/generators/expo_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/expo"

RSpec.describe Whoosh::ClientGen::Generators::Expo do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          refresh: { method: :post, path: "/auth/refresh" },
          logout: { method: :delete, path: "/auth/logout" },
          me: { method: :get, path: "/auth/me" }
        }
      ),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index, pagination: true),
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks/:id", action: :show),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
            Whoosh::ClientGen::IR::Endpoint.new(method: :put, path: "/tasks/:id", action: :update),
            Whoosh::ClientGen::IR::Endpoint.new(method: :delete, path: "/tasks/:id", action: :destroy)
          ],
          fields: [
            { name: :title, type: :string, required: true },
            { name: :description, type: :string, required: false },
            { name: :status, type: :string, required: false, enum: %w[pending in_progress done], default: "pending" }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates a complete Expo project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      expect(File.exist?(File.join(dir, "package.json"))).to be true
      expect(File.exist?(File.join(dir, "app.json"))).to be true
      expect(File.exist?(File.join(dir, "tsconfig.json"))).to be true
      expect(File.exist?(File.join(dir, ".env"))).to be true
    end
  end

  it "uses Expo Router file-based routing" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      expect(File.exist?(File.join(dir, "app", "_layout.tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(auth)", "login.tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(auth)", "register.tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(app)", "tasks", "index.tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(app)", "tasks", "[id].tsx"))).to be true
      expect(File.exist?(File.join(dir, "app", "(app)", "tasks", "form.tsx"))).to be true
    end
  end

  it "uses SecureStore for token storage" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      auth_store = File.read(File.join(dir, "src", "store", "auth.ts"))
      expect(auth_store).to include("SecureStore")
    end
  end

  it "generates typed API client" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      client = File.read(File.join(dir, "src", "api", "client.ts"))
      expect(client).to include("Authorization")
      expect(client).to include("Bearer")
    end
  end

  it "generates resource API and hooks" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      expect(File.exist?(File.join(dir, "src", "api", "tasks.ts"))).to be true
      expect(File.exist?(File.join(dir, "src", "hooks", "useTasks.ts"))).to be true
    end
  end

  it "package.json includes expo dependencies" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      pkg = File.read(File.join(dir, "package.json"))
      expect(pkg).to include("expo")
      expect(pkg).to include("expo-router")
      expect(pkg).to include("expo-secure-store")
    end
  end
end
