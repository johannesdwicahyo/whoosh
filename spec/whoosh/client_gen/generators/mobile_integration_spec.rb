# spec/whoosh/client_gen/generators/mobile_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/expo"
require "whoosh/client_gen/generators/ios"
require "whoosh/client_gen/generators/flutter"
require "whoosh/client_gen/generators/telegram_bot"

RSpec.describe "Mobile & Bot Client Generators Integration" do
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
            { name: :status, type: :string, required: false }
          ]
        ),
        Whoosh::ClientGen::IR::Resource.new(
          name: :comments,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/comments", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/comments", action: :create)
          ],
          fields: [
            { name: :body, type: :string, required: true }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  { expo: :typescript, ios: :swift, flutter: :dart, telegram_bot: :ruby }.each do |client_type, platform|
    describe "#{client_type} with multiple resources" do
      it "generates files for all resources" do
        Dir.mktmpdir do |dir|
          klass = Whoosh::ClientGen::Generators.const_get(
            client_type.to_s.split("_").map(&:capitalize).join
          )
          klass.new(ir: ir, output_dir: dir, platform: platform).generate

          files = Dir.glob("#{dir}/**/*").select { |f| File.file?(f) }
          relative_paths = files.map { |f| f.sub("#{dir}/", "") }.join(" ").downcase

          expect(relative_paths).to include("task")
          expect(relative_paths).to include("comment")
        end
      end
    end
  end
end
