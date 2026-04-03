# spec/whoosh/client_gen/generators/telegram_mini_app_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/telegram_mini_app"

RSpec.describe Whoosh::ClientGen::Generators::TelegramMiniApp do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" }
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

  it "generates a complete Telegram Mini App project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      expect(File.exist?(File.join(dir, "package.json"))).to be true
      expect(File.exist?(File.join(dir, "tsconfig.json"))).to be true
      expect(File.exist?(File.join(dir, "vite.config.ts"))).to be true
      expect(File.exist?(File.join(dir, "index.html"))).to be true
      expect(File.exist?(File.join(dir, ".env"))).to be true
    end
  end

  it "includes @twa-dev/sdk in package.json" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      pkg = File.read(File.join(dir, "package.json"))
      expect(pkg).to include("@twa-dev/sdk")
    end
  end

  it "generates useTelegram hook" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      hook = File.read(File.join(dir, "src", "hooks", "useTelegram.ts"))
      expect(hook).to include("WebApp")
      expect(hook).to include("initData")
    end
  end

  it "generates API client with initData auth" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      client = File.read(File.join(dir, "src", "api", "client.ts"))
      expect(client).to include("initData")
    end
  end

  it "generates MainButton component" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      expect(File.exist?(File.join(dir, "src", "components", "MainButton.tsx"))).to be true
    end
  end

  it "does not generate Login or Register pages" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      expect(File.exist?(File.join(dir, "src", "pages", "Login.tsx"))).to be false
      expect(File.exist?(File.join(dir, "src", "pages", "Register.tsx"))).to be false
    end
  end

  it ".env contains BOT_USERNAME" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :typescript).generate
      env = File.read(File.join(dir, ".env"))
      expect(env).to include("VITE_BOT_USERNAME")
      expect(env).to include("VITE_API_URL")
    end
  end
end
