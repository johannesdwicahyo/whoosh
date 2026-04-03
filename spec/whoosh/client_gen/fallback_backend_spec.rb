# spec/whoosh/client_gen/fallback_backend_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/fallback_backend"

RSpec.describe Whoosh::ClientGen::FallbackBackend do
  describe ".generate" do
    it "creates auth and tasks endpoints" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        expect(File.exist?(File.join(dir, "endpoints", "auth_endpoint.rb"))).to be true
        expect(File.exist?(File.join(dir, "endpoints", "tasks_endpoint.rb"))).to be true
      end
    end

    it "creates auth and task schemas" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        expect(File.exist?(File.join(dir, "schemas", "auth_schemas.rb"))).to be true
        expect(File.exist?(File.join(dir, "schemas", "task_schemas.rb"))).to be true
      end
    end

    it "creates database migrations" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        migrations = Dir.glob(File.join(dir, "db", "migrations", "*.rb"))
        expect(migrations.length).to eq(2)
        names = migrations.map { |f| File.basename(f) }
        expect(names.any? { |n| n.include?("create_users") }).to be true
        expect(names.any? { |n| n.include?("create_tasks") }).to be true
      end
    end

    it "auth endpoint includes bcrypt password hashing" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        content = File.read(File.join(dir, "endpoints", "auth_endpoint.rb"))
        expect(content).to include("BCrypt::Password")
        expect(content).to include("/auth/login")
        expect(content).to include("/auth/register")
        expect(content).to include("/auth/refresh")
        expect(content).to include("/auth/logout")
        expect(content).to include("/auth/me")
      end
    end

    it "tasks endpoint has full CRUD" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        content = File.read(File.join(dir, "endpoints", "tasks_endpoint.rb"))
        expect(content).to include('get "/tasks"')
        expect(content).to include('get "/tasks/:id"')
        expect(content).to include('post "/tasks"')
        expect(content).to include('put "/tasks/:id"')
        expect(content).to include('delete "/tasks/:id"')
      end
    end

    it "includes oauth endpoints when oauth: true" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: true)

        content = File.read(File.join(dir, "endpoints", "auth_endpoint.rb"))
        expect(content).to include("/auth/:provider")
        expect(content).to include("/auth/:provider/callback")
      end
    end
  end
end
