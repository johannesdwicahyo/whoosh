# lib/whoosh/client_gen/fallback_backend.rb
# frozen_string_literal: true

require "fileutils"

module Whoosh
  module ClientGen
    class FallbackBackend
      def self.generate(root: Dir.pwd, oauth: false)
        new(root: root, oauth: oauth).generate
      end

      def initialize(root:, oauth:)
        @root = root
        @oauth = oauth
      end

      def generate
        generate_schemas
        generate_auth_endpoint
        generate_tasks_endpoint
        generate_migrations
      end

      private

      def write_file(relative_path, content)
        path = File.join(@root, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def generate_schemas
        write_file("schemas/auth_schemas.rb", auth_schemas_content)
        write_file("schemas/task_schemas.rb", task_schemas_content)
      end

      def generate_auth_endpoint
        write_file("endpoints/auth_endpoint.rb", auth_endpoint_content)
      end

      def generate_tasks_endpoint
        write_file("endpoints/tasks_endpoint.rb", tasks_endpoint_content)
      end

      def generate_migrations
        timestamp = Time.now.strftime("%Y%m%d%H%M%S")
        write_file("db/migrations/#{timestamp}_create_users.rb", create_users_migration)
        write_file("db/migrations/#{timestamp.to_i + 1}_create_tasks.rb", create_tasks_migration)
      end

      def auth_schemas_content
        <<~RUBY
          # frozen_string_literal: true

          class LoginRequest < Whoosh::Schema
            field :email, String, required: true
            field :password, String, required: true
          end

          class RegisterRequest < Whoosh::Schema
            field :name, String, required: true
            field :email, String, required: true
            field :password, String, required: true, min_length: 8
          end

          class TokenResponse < Whoosh::Schema
            field :token, String, required: true
            field :refresh_token, String, required: true
          end

          class UserResponse < Whoosh::Schema
            field :id, Integer, required: true
            field :name, String, required: true
            field :email, String, required: true
          end
        RUBY
      end

      def task_schemas_content
        <<~RUBY
          # frozen_string_literal: true

          class CreateTaskRequest < Whoosh::Schema
            field :title, String, required: true
            field :description, String
            field :status, String, enum: %w[pending in_progress completed]
            field :due_date, String
          end

          class UpdateTaskRequest < Whoosh::Schema
            field :title, String
            field :description, String
            field :status, String, enum: %w[pending in_progress completed]
            field :due_date, String
          end

          class TaskResponse < Whoosh::Schema
            field :id, Integer, required: true
            field :user_id, Integer, required: true
            field :title, String, required: true
            field :description, String
            field :status, String, required: true
            field :due_date, String
            field :created_at, String, required: true
            field :updated_at, String, required: true
          end
        RUBY
      end

      def auth_endpoint_content
        oauth_routes = if @oauth
          <<~'RUBY'

            App.get "/auth/:provider", auth: false do |req, db:|
              provider = req.params[:provider]
              redirect_url = App.oauth.authorize_url(provider: provider)
              { redirect_url: redirect_url }
            end

            App.get "/auth/:provider/callback", auth: false do |req, db:|
              provider = req.params[:provider]
              user_info = App.oauth.handle_callback(provider: provider, params: req.params)
              user = db[:users].where(email: user_info[:email]).first
              unless user
                user = { name: user_info[:name], email: user_info[:email], password_hash: nil }
                user[:id] = db[:users].insert(user.merge(created_at: Time.now, updated_at: Time.now))
              end
              token = App.jwt.generate(sub: user[:id], email: user[:email])
              refresh = App.jwt.generate(sub: user[:id], type: :refresh)
              { token: token, refresh_token: refresh }
            end
          RUBY
        else
          ""
        end

        <<~RUBY
          # frozen_string_literal: true

          App.post "/auth/register", auth: false do |req, db:|
            data = RegisterRequest.validate!(req.body)
            existing = db[:users].where(email: data[:email]).first
            raise Whoosh::Errors::ValidationError, "Email already registered" if existing

            password_hash = BCrypt::Password.create(data[:password])
            user_id = db[:users].insert(
              name: data[:name],
              email: data[:email],
              password_hash: password_hash,
              created_at: Time.now,
              updated_at: Time.now
            )
            token = App.jwt.generate(sub: user_id, email: data[:email])
            refresh = App.jwt.generate(sub: user_id, type: :refresh)
            { token: token, refresh_token: refresh }
          end

          App.post "/auth/login", auth: false do |req, db:|
            data = LoginRequest.validate!(req.body)
            user = db[:users].where(email: data[:email]).first
            raise Whoosh::Errors::UnauthorizedError, "Invalid credentials" unless user

            stored = BCrypt::Password.new(user[:password_hash])
            raise Whoosh::Errors::UnauthorizedError, "Invalid credentials" unless stored == data[:password]

            token = App.jwt.generate(sub: user[:id], email: user[:email])
            refresh = App.jwt.generate(sub: user[:id], type: :refresh)
            { token: token, refresh_token: refresh }
          end

          App.post "/auth/refresh", auth: :jwt do |req, db:|
            user = db[:users].where(id: req.current_user[:sub]).first
            raise Whoosh::Errors::UnauthorizedError, "User not found" unless user

            token = App.jwt.generate(sub: user[:id], email: user[:email])
            refresh = App.jwt.generate(sub: user[:id], type: :refresh)
            { token: token, refresh_token: refresh }
          end

          App.delete "/auth/logout", auth: :jwt do |req, db:|
            App.jwt.revoke(req.token) if App.jwt.respond_to?(:revoke)
            { message: "Logged out successfully" }
          end

          App.get "/auth/me", auth: :jwt do |req, db:|
            user = db[:users].where(id: req.current_user[:sub]).first
            raise Whoosh::Errors::NotFoundError, "User not found" unless user

            { id: user[:id], name: user[:name], email: user[:email] }
          end
        #{oauth_routes}
        RUBY
      end

      def tasks_endpoint_content
        <<~RUBY
          # frozen_string_literal: true

          App.get "/tasks", auth: :jwt do |req, db:|
            dataset = db[:tasks].where(user_id: req.current_user[:sub])
            paginate_cursor(dataset, cursor: req.params[:cursor], limit: req.params.fetch(:limit, 20).to_i)
          end

          App.get "/tasks/:id", auth: :jwt do |req, db:|
            task = db[:tasks].where(id: req.params[:id], user_id: req.current_user[:sub]).first
            raise Whoosh::Errors::NotFoundError, "Task not found" unless task

            task
          end

          App.post "/tasks", auth: :jwt do |req, db:|
            data = CreateTaskRequest.validate!(req.body)
            task_id = db[:tasks].insert(
              user_id: req.current_user[:sub],
              title: data[:title],
              description: data[:description],
              status: data.fetch(:status, "pending"),
              due_date: data[:due_date],
              created_at: Time.now,
              updated_at: Time.now
            )
            db[:tasks].where(id: task_id).first
          end

          App.put "/tasks/:id", auth: :jwt do |req, db:|
            task = db[:tasks].where(id: req.params[:id], user_id: req.current_user[:sub]).first
            raise Whoosh::Errors::NotFoundError, "Task not found" unless task

            data = UpdateTaskRequest.validate!(req.body)
            updates = data.compact.merge(updated_at: Time.now)
            db[:tasks].where(id: req.params[:id]).update(updates)
            db[:tasks].where(id: req.params[:id]).first
          end

          App.delete "/tasks/:id", auth: :jwt do |req, db:|
            task = db[:tasks].where(id: req.params[:id], user_id: req.current_user[:sub]).first
            raise Whoosh::Errors::NotFoundError, "Task not found" unless task

            db[:tasks].where(id: req.params[:id]).delete
            { message: "Task deleted" }
          end
        RUBY
      end

      def create_users_migration
        <<~RUBY
          # frozen_string_literal: true

          Sequel.migration do
            change do
              create_table(:users) do
                primary_key :id
                String :name, null: false
                String :email, null: false
                String :password_hash
                DateTime :created_at, null: false
                DateTime :updated_at, null: false

                index :email, unique: true
              end
            end
          end
        RUBY
      end

      def create_tasks_migration
        <<~RUBY
          # frozen_string_literal: true

          Sequel.migration do
            change do
              create_table(:tasks) do
                primary_key :id
                foreign_key :user_id, :users, null: false
                String :title, null: false
                Text :description
                String :status, default: "pending"
                Date :due_date
                DateTime :created_at, null: false
                DateTime :updated_at, null: false

                index :user_id
                index :status
              end
            end
          end
        RUBY
      end
    end
  end
end
