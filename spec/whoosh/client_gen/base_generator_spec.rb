# spec/whoosh/client_gen/base_generator_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/base_generator"
require "whoosh/client_gen/ir"

RSpec.describe Whoosh::ClientGen::BaseGenerator do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(type: :jwt, endpoints: {
        login: { method: :post, path: "/auth/login" },
        register: { method: :post, path: "/auth/register" }
      }),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create)
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

  describe "#type_for" do
    it "maps IR types to TypeScript types" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :typescript)
      expect(gen.type_for(:string)).to eq("string")
      expect(gen.type_for(:integer)).to eq("number")
      expect(gen.type_for(:boolean)).to eq("boolean")
    end

    it "maps IR types to Swift types" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :swift)
      expect(gen.type_for(:string)).to eq("String")
      expect(gen.type_for(:integer)).to eq("Int")
      expect(gen.type_for(:boolean)).to eq("Bool")
    end

    it "maps IR types to Dart types" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :dart)
      expect(gen.type_for(:string)).to eq("String")
      expect(gen.type_for(:integer)).to eq("int")
      expect(gen.type_for(:boolean)).to eq("bool")
    end
  end

  describe "#write_file" do
    it "creates files with directories" do
      Dir.mktmpdir do |dir|
        gen = described_class.new(ir: ir, output_dir: dir, platform: :typescript)
        gen.write_file("src/api/client.ts", "export const API_URL = 'test';")

        path = File.join(dir, "src/api/client.ts")
        expect(File.exist?(path)).to be true
        expect(File.read(path)).to eq("export const API_URL = 'test';")
      end
    end
  end

  describe "#classify" do
    it "converts resource names to class names" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :typescript)
      expect(gen.classify(:tasks)).to eq("Task")
      expect(gen.classify(:user_profiles)).to eq("UserProfile")
    end
  end

  describe "#singularize" do
    it "removes trailing s" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :typescript)
      expect(gen.singularize("tasks")).to eq("task")
      expect(gen.singularize("statuses")).to eq("status")
    end
  end
end
