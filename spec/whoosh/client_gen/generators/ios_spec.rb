# spec/whoosh/client_gen/generators/ios_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/ios"

RSpec.describe Whoosh::ClientGen::Generators::Ios do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          logout: { method: :delete, path: "/auth/logout" },
          me: { method: :get, path: "/auth/me" }
        }
      ),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks/:id", action: :show),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
            Whoosh::ClientGen::IR::Endpoint.new(method: :put, path: "/tasks/:id", action: :update),
            Whoosh::ClientGen::IR::Endpoint.new(method: :delete, path: "/tasks/:id", action: :destroy)
          ],
          fields: [
            { name: :title, type: :string, required: true },
            { name: :description, type: :string, required: false },
            { name: :status, type: :string, required: false, enum: %w[pending in_progress done] }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates a complete iOS project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate
      expect(File.exist?(File.join(dir, "WhooshApp", "App.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp.xcodeproj", "project.pbxproj"))).to be true
    end
  end

  it "generates Codable model structs" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate
      model = File.read(File.join(dir, "WhooshApp", "Models", "Task.swift"))
      expect(model).to include("struct Task")
      expect(model).to include("Codable")
      expect(model).to include("var title: String")
    end
  end

  it "generates APIClient with auth interceptor" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate
      client = File.read(File.join(dir, "WhooshApp", "API", "APIClient.swift"))
      expect(client).to include("URLSession")
      expect(client).to include("Authorization")
      expect(client).to include("Bearer")
    end
  end

  it "generates KeychainHelper" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate
      keychain = File.read(File.join(dir, "WhooshApp", "Keychain", "KeychainHelper.swift"))
      expect(keychain).to include("SecItemAdd")
      expect(keychain).to include("kSecClass")
    end
  end

  it "generates SwiftUI views" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Auth", "LoginView.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Auth", "RegisterView.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Tasks", "TaskListView.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Tasks", "TaskDetailView.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "Views", "Tasks", "TaskFormView.swift"))).to be true
    end
  end

  it "generates ViewModels" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :swift).generate
      expect(File.exist?(File.join(dir, "WhooshApp", "ViewModels", "AuthViewModel.swift"))).to be true
      expect(File.exist?(File.join(dir, "WhooshApp", "ViewModels", "TaskViewModel.swift"))).to be true
    end
  end
end
