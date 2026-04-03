# spec/whoosh/client_gen/generators/htmx_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/htmx"

RSpec.describe Whoosh::ClientGen::Generators::Htmx do
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
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks/:id", action: :show),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
            Whoosh::ClientGen::IR::Endpoint.new(method: :put, path: "/tasks/:id", action: :update),
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

  it "generates index.html with htmx script" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate
      index = File.read(File.join(dir, "index.html"))
      expect(index).to include("htmx")
      expect(index).to include("<!DOCTYPE html>")
    end
  end

  it "generates auth pages" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate
      expect(File.exist?(File.join(dir, "pages", "auth", "login.html"))).to be true
      expect(File.exist?(File.join(dir, "pages", "auth", "register.html"))).to be true
      login = File.read(File.join(dir, "pages", "auth", "login.html"))
      expect(login).to include("hx-post")
      expect(login).to include("/auth/login")
    end
  end

  it "generates resource pages" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate
      expect(File.exist?(File.join(dir, "pages", "tasks", "index.html"))).to be true
      expect(File.exist?(File.join(dir, "pages", "tasks", "form.html"))).to be true
    end
  end

  it "generates auth.js for token management" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate
      auth = File.read(File.join(dir, "js", "auth.js"))
      expect(auth).to include("localStorage")
      expect(auth).to include("Authorization")
    end
  end

  it "generates config.js with API_URL" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate
      config = File.read(File.join(dir, "config.js"))
      expect(config).to include("http://localhost:9292")
    end
  end

  it "generates css/style.css" do
    Dir.mktmpdir do |dir|
      described_class.new(ir: ir, output_dir: dir, platform: :html).generate
      expect(File.exist?(File.join(dir, "css", "style.css"))).to be true
    end
  end
end
