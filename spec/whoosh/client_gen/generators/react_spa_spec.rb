# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/react_spa"

RSpec.describe Whoosh::ClientGen::Generators::ReactSpa do
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
        },
        oauth_providers: []
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
            { name: :status, type: :string, required: false, enum: %w[pending in_progress done], default: "pending" },
            { name: :due_date, type: :string, required: false }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  it "generates a complete React SPA project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "package.json"))).to be true
      expect(File.exist?(File.join(dir, "tsconfig.json"))).to be true
      expect(File.exist?(File.join(dir, "vite.config.ts"))).to be true
      expect(File.exist?(File.join(dir, "index.html"))).to be true
      expect(File.exist?(File.join(dir, ".env"))).to be true
    end
  end

  it "generates typed API client" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      client = File.read(File.join(dir, "src", "api", "client.ts"))
      expect(client).to include("API_URL")
      expect(client).to include("Authorization")
      expect(client).to include("Bearer")
    end
  end

  it "generates auth API module" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      auth = File.read(File.join(dir, "src", "api", "auth.ts"))
      expect(auth).to include("login")
      expect(auth).to include("register")
      expect(auth).to include("logout")
      expect(auth).to include("refresh")
    end
  end

  it "generates resource API module for tasks" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      tasks = File.read(File.join(dir, "src", "api", "tasks.ts"))
      expect(tasks).to include("listTasks")
      expect(tasks).to include("getTask")
      expect(tasks).to include("createTask")
      expect(tasks).to include("updateTask")
      expect(tasks).to include("deleteTask")
    end
  end

  it "generates TypeScript model interfaces" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      model = File.read(File.join(dir, "src", "models", "task.ts"))
      expect(model).to include("interface Task")
      expect(model).to include("title: string")
      expect(model).to include("status: string")
    end
  end

  it "generates React pages" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "pages", "Login.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "pages", "Register.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "pages", "TaskList.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "pages", "TaskDetail.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "pages", "TaskForm.tsx"))).to be true
    end
  end

  it "generates hooks" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "hooks", "useAuth.ts"))).to be true
      expect(File.exist?(File.join(dir, "src", "hooks", "useTasks.ts"))).to be true
    end
  end

  it "generates router, App, and main entry" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "router.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "App.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "main.tsx"))).to be true
    end
  end

  it "generates components" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      expect(File.exist?(File.join(dir, "src", "components", "Layout.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "components", "ProtectedRoute.tsx"))).to be true
      expect(File.exist?(File.join(dir, "src", "components", "Pagination.tsx"))).to be true
    end
  end

  it "package.json includes correct dependencies" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      pkg = File.read(File.join(dir, "package.json"))
      expect(pkg).to include("react")
      expect(pkg).to include("react-router-dom")
      expect(pkg).to include("vite")
      expect(pkg).to include("typescript")
    end
  end

  it ".env contains API_URL" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate

      env = File.read(File.join(dir, ".env"))
      expect(env).to include("VITE_API_URL=http://localhost:9292")
    end
  end
end
