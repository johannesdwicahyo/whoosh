# spec/whoosh/client_gen/generators/flutter_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/flutter"

RSpec.describe Whoosh::ClientGen::Generators::Flutter do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          logout: { method: :delete, path: "/auth/logout" }
        }
      ),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
            Whoosh::ClientGen::IR::Endpoint.new(method: :delete, path: "/tasks/:id", action: :destroy)
          ],
          fields: [
            { name: :title, type: :string, required: true },
            { name: :status, type: :string, required: false, enum: %w[pending done] }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates a complete Flutter project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate
      expect(File.exist?(File.join(dir, "pubspec.yaml"))).to be true
      expect(File.exist?(File.join(dir, "lib", "main.dart"))).to be true
    end
  end

  it "generates Dart model classes" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate
      model = File.read(File.join(dir, "lib", "models", "task.dart"))
      expect(model).to include("class Task")
      expect(model).to include("String title")
      expect(model).to include("fromJson")
      expect(model).to include("toJson")
    end
  end

  it "generates API client with Dio" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate
      client = File.read(File.join(dir, "lib", "api", "client.dart"))
      expect(client).to include("Dio")
      expect(client).to include("Authorization")
    end
  end

  it "generates auth and resource services" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate
      expect(File.exist?(File.join(dir, "lib", "api", "auth_service.dart"))).to be true
      expect(File.exist?(File.join(dir, "lib", "api", "task_service.dart"))).to be true
    end
  end

  it "generates screen files" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate
      expect(File.exist?(File.join(dir, "lib", "screens", "auth", "login_screen.dart"))).to be true
      expect(File.exist?(File.join(dir, "lib", "screens", "auth", "register_screen.dart"))).to be true
      expect(File.exist?(File.join(dir, "lib", "screens", "tasks", "task_list_screen.dart"))).to be true
    end
  end

  it "generates providers" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate
      expect(File.exist?(File.join(dir, "lib", "providers", "auth_provider.dart"))).to be true
      expect(File.exist?(File.join(dir, "lib", "providers", "task_provider.dart"))).to be true
    end
  end

  it "generates GoRouter configuration" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate
      router = File.read(File.join(dir, "lib", "router.dart"))
      expect(router).to include("GoRouter")
      expect(router).to include("/tasks")
      expect(router).to include("/login")
    end
  end

  it "pubspec.yaml includes correct dependencies" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :dart).generate
      pubspec = File.read(File.join(dir, "pubspec.yaml"))
      expect(pubspec).to include("dio:")
      expect(pubspec).to include("flutter_riverpod:")
      expect(pubspec).to include("go_router:")
      expect(pubspec).to include("flutter_secure_storage:")
    end
  end
end
