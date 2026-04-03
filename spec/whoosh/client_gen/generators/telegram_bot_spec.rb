# spec/whoosh/client_gen/generators/telegram_bot_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/telegram_bot"

RSpec.describe Whoosh::ClientGen::Generators::TelegramBot do
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

  it "generates a complete Telegram bot project" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate
      expect(File.exist?(File.join(dir, "bot.rb"))).to be true
      expect(File.exist?(File.join(dir, "Gemfile"))).to be true
      expect(File.exist?(File.join(dir, "config.yml"))).to be true
    end
  end

  it "generates API client" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate
      client = File.read(File.join(dir, "lib", "api", "client.rb"))
      expect(client).to include("Net::HTTP")
      expect(client).to include("Authorization")
      expect(client).to include("Bearer")
    end
  end

  it "generates command handlers" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate
      expect(File.exist?(File.join(dir, "lib", "handlers", "start_handler.rb"))).to be true
      expect(File.exist?(File.join(dir, "lib", "handlers", "auth_handler.rb"))).to be true
      expect(File.exist?(File.join(dir, "lib", "handlers", "task_handler.rb"))).to be true

      task_handler = File.read(File.join(dir, "lib", "handlers", "task_handler.rb"))
      expect(task_handler).to include("/tasks")
      expect(task_handler).to include("/new")
    end
  end

  it "generates session store" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate
      store = File.read(File.join(dir, "lib", "session", "store.rb"))
      expect(store).to include("token")
    end
  end

  it "generates inline keyboards" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate
      keyboards = File.read(File.join(dir, "lib", "keyboards", "inline_keyboards.rb"))
      expect(keyboards).to include("InlineKeyboardButton")
    end
  end

  it "Gemfile includes telegram-bot-ruby" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate
      gemfile = File.read(File.join(dir, "Gemfile"))
      expect(gemfile).to include("telegram-bot-ruby")
    end
  end

  it "config.yml contains BOT_TOKEN and API_URL" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :ruby).generate
      config = File.read(File.join(dir, "config.yml"))
      expect(config).to include("bot_token")
      expect(config).to include("api_url")
      expect(config).to include("http://localhost:9292")
    end
  end
end
