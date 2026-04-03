# spec/whoosh/client_gen/generators/web_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/ir"
require "whoosh/client_gen/generators/react_spa"
require "whoosh/client_gen/generators/htmx"
require "whoosh/client_gen/generators/telegram_mini_app"

RSpec.describe "Web Client Generators Integration" do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
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
        ),
        Whoosh::ClientGen::IR::Resource.new(
          name: :notes,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/notes", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/notes", action: :create)
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

  %i[react_spa htmx telegram_mini_app].each do |client_type|
    describe "#{client_type} with multiple resources" do
      it "generates files for all resources" do
        Dir.mktmpdir do |dir|
          klass = case client_type
                  when :react_spa then Whoosh::ClientGen::Generators::ReactSpa
                  when :htmx then Whoosh::ClientGen::Generators::Htmx
                  when :telegram_mini_app then Whoosh::ClientGen::Generators::TelegramMiniApp
                  end
          platform = client_type == :htmx ? :html : :typescript

          klass.new(ir: ir, output_dir: dir, platform: platform).generate

          files = Dir.glob("#{dir}/**/*").select { |f| File.file?(f) }
          relative_paths = files.map { |f| f.sub("#{dir}/", "") }.join(" ")

          expect(relative_paths).to include("task")
          expect(relative_paths).to include("note")
        end
      end
    end
  end
end
