# frozen_string_literal: true

require "whoosh/client_gen/base_generator"

module Whoosh
  module ClientGen
    module Generators
      class TelegramBot < BaseGenerator
        def generate
          generate_root_files
          generate_api_client
          generate_auth_service
          ir.resources.each { |r| generate_resource_service(r) }
          generate_handlers
          ir.resources.each { |r| generate_resource_handler(r) }
          generate_session_store
          generate_inline_keyboards
          generate_readme
        end

        private

        # ── Root files ────────────────────────────────────────────────

        def generate_root_files
          write_file("bot.rb", bot_rb)
          write_file("Gemfile", gemfile)
          write_file("config.yml", config_yml)
          write_file(".env", dot_env)
          write_file(".gitignore", gitignore)
        end

        def bot_rb
          require_services = ir.resources.map do |r|
            plural = r.name.to_s
            singular = singularize(plural)
            "require_relative \"lib/api/#{singular}_service\""
          end.join("\n")

          handler_requires = ir.resources.map do |r|
            singular = singularize(r.name.to_s)
            "require_relative \"lib/handlers/#{singular}_handler\""
          end.join("\n")

          service_inits = ir.resources.map do |r|
            plural = r.name.to_s
            singular = singularize(plural)
            name = classify(r.name)
            "#{singular}_service = #{name}Service.new(client)"
          end.join("\n")

          handler_inits = ir.resources.map do |r|
            plural = r.name.to_s
            singular = singularize(plural)
            name = classify(r.name)
            "#{singular}_handler = #{name}Handler.new(bot, sessions, #{singular}_service)"
          end.join("\n")

          handler_dispatch = ir.resources.map do |r|
            singular = singularize(r.name.to_s)
            "  #{singular}_handler.handle(message)"
          end.join("\n")

          callback_dispatch = ir.resources.map do |r|
            singular = singularize(r.name.to_s)
            "  #{singular}_handler.handle_callback(query)"
          end.join("\n")

          <<~RUBY
            # frozen_string_literal: true

            require "telegram/bot"
            require "yaml"
            require_relative "lib/api/client"
            require_relative "lib/api/auth_service"
            #{require_services}
            require_relative "lib/handlers/start_handler"
            require_relative "lib/handlers/auth_handler"
            #{handler_requires}
            require_relative "lib/session/store"

            config = YAML.load_file(File.join(__dir__, "config.yml"))
            token  = ENV["BOT_TOKEN"] || config.dig("bot_token") || raise("BOT_TOKEN not set")
            api_url = ENV["API_URL"] || config.dig("api_url") || "#{ir.base_url}"

            sessions     = SessionStore.new
            client       = ApiClient.new(base_url: api_url)
            auth_service = AuthService.new(client)
            #{service_inits}

            start_handler = StartHandler.new(bot: nil, sessions: sessions)
            auth_handler  = AuthHandler.new(bot: nil, sessions: sessions, auth_service: auth_service)
            #{handler_inits.gsub("(bot,", "(bot: nil,")}

            Telegram::Bot::Client.run(token) do |bot|
              start_handler.bot  = bot
              auth_handler.bot   = bot
            #{ir.resources.map { |r| "  #{singularize(r.name.to_s)}_handler.bot = bot" }.join("\n")}

              bot.listen do |update|
                case update
                when Telegram::Bot::Types::Message
                  message = update
                  start_handler.handle(message)
                  auth_handler.handle(message)
            #{handler_dispatch}
                when Telegram::Bot::Types::CallbackQuery
                  query = update
            #{callback_dispatch}
                end
              end
            end
          RUBY
        end

        def gemfile
          <<~RUBY
            # frozen_string_literal: true

            source "https://rubygems.org"

            gem "telegram-bot-ruby", "~> 0.19"
            gem "net-http"
            gem "json"
            gem "yaml"
          RUBY
        end

        def config_yml
          <<~YAML
            bot_token: <%= ENV["BOT_TOKEN"] || "YOUR_BOT_TOKEN_HERE" %>
            api_url: "#{ir.base_url}"
          YAML
        end

        def dot_env
          <<~ENV
            BOT_TOKEN=your_telegram_bot_token_here
            API_URL=#{ir.base_url}
          ENV
        end

        def gitignore
          <<~TXT
            .env
            *.log
            tmp/
          TXT
        end

        # ── API client ────────────────────────────────────────────────

        def generate_api_client
          write_file("lib/api/client.rb", <<~RUBY)
            # frozen_string_literal: true

            require "net/http"
            require "uri"
            require "json"

            class ApiClient
              def initialize(base_url:)
                @base_url = base_url
              end

              def get(path, token: nil)
                request(:get, path, body: nil, token: token)
              end

              def post(path, body:, token: nil)
                request(:post, path, body: body, token: token)
              end

              def put(path, body:, token: nil)
                request(:put, path, body: body, token: token)
              end

              def delete(path, token: nil)
                request(:delete, path, body: nil, token: token)
              end

              private

              def request(method, path, body:, token:)
                uri  = URI.parse("\#{@base_url}\#{path.start_with?("/") ? "" : "/"}\#{path}")
                http = Net::HTTP.new(uri.host, uri.port)
                http.use_ssl = uri.scheme == "https"

                req_class = {
                  get: Net::HTTP::Get,
                  post: Net::HTTP::Post,
                  put: Net::HTTP::Put,
                  delete: Net::HTTP::Delete
                }[method]

                req = req_class.new(uri.request_uri)
                req["Content-Type"] = "application/json"
                req["Accept"]       = "application/json"

                if token
                  req["Authorization"] = "Bearer \#{token}"
                end

                req.body = body.to_json if body

                res = http.request(req)
                return nil if res.code.to_i == 204

                JSON.parse(res.body)
              rescue StandardError => e
                { "error" => e.message }
              end
            end
          RUBY
        end

        # ── Auth service ──────────────────────────────────────────────

        def generate_auth_service
          login_path  = ir.auth&.endpoints&.dig(:login, :path)  || "/auth/login"
          reg_path    = ir.auth&.endpoints&.dig(:register, :path) || "/auth/register"

          write_file("lib/api/auth_service.rb", <<~RUBY)
            # frozen_string_literal: true

            class AuthService
              def initialize(client)
                @client = client
              end

              def login(email:, password:)
                @client.post("#{login_path}", body: { email: email, password: password })
              end

              def register(name:, email:, password:)
                @client.post("#{reg_path}", body: { name: name, email: email, password: password })
              end
            end
          RUBY
        end

        # ── Resource services ─────────────────────────────────────────

        def generate_resource_service(resource)
          plural   = resource.name.to_s
          singular = singularize(plural)
          name     = classify(resource.name)

          write_file("lib/api/#{singular}_service.rb", <<~RUBY)
            # frozen_string_literal: true

            class #{name}Service
              def initialize(client)
                @client = client
              end

              def list(token:)
                @client.get("/#{plural}", token: token)
              end

              def find(id, token:)
                @client.get("/#{plural}/\#{id}", token: token)
              end

              def create(attrs, token:)
                @client.post("/#{plural}", body: attrs, token: token)
              end

              def update(id, attrs, token:)
                @client.put("/#{plural}/\#{id}", body: attrs, token: token)
              end

              def destroy(id, token:)
                @client.delete("/#{plural}/\#{id}", token: token)
              end
            end
          RUBY
        end

        # ── Generic handlers ──────────────────────────────────────────

        def generate_handlers
          generate_start_handler
          generate_auth_handler
        end

        def generate_start_handler
          resource_menu = ir.resources.map do |r|
            plural = r.name.to_s
            "/#{plural} — manage #{plural}"
          end.join("\\n")

          write_file("lib/handlers/start_handler.rb", <<~RUBY)
            # frozen_string_literal: true

            class StartHandler
              attr_accessor :bot

              def initialize(bot:, sessions:)
                @bot      = bot
                @sessions = sessions
              end

              def handle(message)
                return unless message.respond_to?(:text) && message.text

                case message.text.strip
                when "/start"
                  chat_id = message.chat.id
                  session = @sessions.get(chat_id)
                  if session[:token]
                    send_message(chat_id, welcome_menu)
                  else
                    send_message(chat_id, "Welcome! Please log in first.\\n/login <email> <password>\\n/register <name> <email> <password>")
                  end
                end
              end

              private

              def welcome_menu
                "What would you like to do?\\n#{resource_menu}\\n/logout"
              end

              def send_message(chat_id, text)
                @bot&.api&.send_message(chat_id: chat_id, text: text)
              end
            end
          RUBY
        end

        def generate_auth_handler
          write_file("lib/handlers/auth_handler.rb", <<~RUBY)
            # frozen_string_literal: true

            class AuthHandler
              attr_accessor :bot

              def initialize(bot:, sessions:, auth_service:)
                @bot          = bot
                @sessions     = sessions
                @auth_service = auth_service
              end

              def handle(message)
                return unless message.respond_to?(:text) && message.text

                chat_id = message.chat.id
                text    = message.text.strip

                case text
                when /^\/login\\s+(\\S+)\\s+(\\S+)$/
                  handle_login(chat_id, $1, $2)
                when /^\/register\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)$/
                  handle_register(chat_id, $1, $2, $3)
                when "/logout"
                  handle_logout(chat_id)
                end
              end

              private

              def handle_login(chat_id, email, password)
                result = @auth_service.login(email: email, password: password)
                if result && result["access_token"]
                  @sessions.set(chat_id, token: result["access_token"])
                  send_message(chat_id, "Logged in successfully!")
                else
                  send_message(chat_id, "Login failed. Check your credentials.")
                end
              end

              def handle_register(chat_id, name, email, password)
                result = @auth_service.register(name: name, email: email, password: password)
                if result && result["access_token"]
                  @sessions.set(chat_id, token: result["access_token"])
                  send_message(chat_id, "Registered and logged in!")
                else
                  send_message(chat_id, "Registration failed.")
                end
              end

              def handle_logout(chat_id)
                @sessions.clear(chat_id)
                send_message(chat_id, "Logged out. See you next time!")
              end

              def send_message(chat_id, text)
                @bot&.api&.send_message(chat_id: chat_id, text: text)
              end
            end
          RUBY
        end

        # ── Resource handlers ─────────────────────────────────────────

        def generate_resource_handler(resource)
          plural   = resource.name.to_s
          singular = singularize(plural)
          name     = classify(resource.name)
          fields   = resource.fields || []

          required_fields = fields.select { |f| f[:required] }
          field_names     = fields.map { |f| f[:name].to_s }

          create_parse = required_fields.map.with_index do |f, i|
            "#{f[:name]} = parts[#{i + 1}]"
          end.join("\n    ")

          create_body = fields.map do |f|
            "#{f[:name]}: #{f[:name]}"
          end.join(", ")

          write_file("lib/handlers/#{singular}_handler.rb", <<~RUBY)
            # frozen_string_literal: true

            class #{name}Handler
              attr_accessor :bot

              COMMANDS = %w[/#{plural} /new /delete].freeze

              def initialize(bot, sessions, #{singular}_service)
                @bot     = bot
                @sessions = sessions
                @service = #{singular}_service
              end

              def handle(message)
                return unless message.respond_to?(:text) && message.text

                chat_id = message.chat.id
                text    = message.text.strip
                session = @sessions.get(chat_id)
                token   = session[:token]

                case text
                when "/#{plural}"
                  handle_list(chat_id, token)
                when /^\\/new\\s+(.+)$/
                  handle_new(chat_id, $1, token)
                when /^\\/delete_(\\d+)$/, /^\\/delete\\s+(\\S+)$/
                  handle_delete(chat_id, $1, token)
                end
              end

              def handle_callback(query)
                return unless query.respond_to?(:data) && query.data

                chat_id = query.message.chat.id
                data    = query.data
                session = @sessions.get(chat_id)
                token   = session[:token]

                if data.start_with?("delete_#{singular}_")
                  id = data.sub("delete_#{singular}_", "")
                  handle_delete(chat_id, id, token)
                  @bot&.api&.answer_callback_query(callback_query_id: query.id)
                end
              end

              private

              def handle_list(chat_id, token)
                unless token
                  send_message(chat_id, "Please /login first.")
                  return
                end
                items = @service.list(token: token)
                if items.is_a?(Array) && !items.empty?
                  lines = items.map.with_index(1) do |item, i|
                    label = item["title"] || item["name"] || item["id"]
                    "\#{i}. \#{label} [/delete_\#{item["id"]}]"
                  end
                  send_message(chat_id, "#{name}s:\\n\#{lines.join("\\n")}")
                else
                  send_message(chat_id, "No #{plural} found. Use /new <title> to create one.")
                end
              end

              def handle_new(chat_id, title, token)
                unless token
                  send_message(chat_id, "Please /login first.")
                  return
                end
                result = @service.create({ title: title }, token: token)
                if result && !result["error"]
                  send_message(chat_id, "#{name} created!")
                else
                  send_message(chat_id, "Failed to create #{singular}.")
                end
              end

              def handle_delete(chat_id, id, token)
                unless token
                  send_message(chat_id, "Please /login first.")
                  return
                end
                @service.destroy(id, token: token)
                send_message(chat_id, "#{name} \#{id} deleted.")
              end

              def send_message(chat_id, text)
                @bot&.api&.send_message(chat_id: chat_id, text: text)
              end
            end
          RUBY
        end

        # ── Session store ─────────────────────────────────────────────

        def generate_session_store
          write_file("lib/session/store.rb", <<~RUBY)
            # frozen_string_literal: true

            class SessionStore
              def initialize
                @sessions = {}
              end

              def get(chat_id)
                @sessions[chat_id] ||= { token: nil, state: nil, data: {} }
              end

              def set(chat_id, **attrs)
                session = get(chat_id)
                attrs.each { |k, v| session[k] = v }
                session
              end

              def clear(chat_id)
                @sessions.delete(chat_id)
              end

              def token(chat_id)
                get(chat_id)[:token]
              end

              def authenticated?(chat_id)
                !get(chat_id)[:token].nil?
              end
            end
          RUBY
        end

        # ── Inline keyboards ──────────────────────────────────────────

        def generate_inline_keyboards
          resource_keyboards = ir.resources.map do |r|
            plural   = r.name.to_s
            singular = singularize(plural)
            name     = classify(r.name)

            <<~RUBY.chomp
              def self.#{singular}_actions(id)
                Telegram::Bot::Types::InlineKeyboardMarkup.new(
                  inline_keyboard: [[
                    Telegram::Bot::Types::InlineKeyboardButton.new(
                      text: "Delete",
                      callback_data: "delete_#{singular}_\#{id}"
                    )
                  ]]
                )
              end
            RUBY
          end.join("\n\n  ")

          write_file("lib/keyboards/inline_keyboards.rb", <<~RUBY)
            # frozen_string_literal: true

            class InlineKeyboards
              #{resource_keyboards}

              def self.main_menu
                Telegram::Bot::Types::InlineKeyboardMarkup.new(
                  inline_keyboard: [
            #{ir.resources.map { |r| "        [Telegram::Bot::Types::InlineKeyboardButton.new(text: \"#{classify(r.name)}s\", callback_data: \"menu_#{r.name}\")]" }.join(",\n")}
                  ]
                )
              end
            end
          RUBY
        end

        # ── README ────────────────────────────────────────────────────

        def generate_readme
          resource_commands = ir.resources.map do |r|
            plural   = r.name.to_s
            singular = singularize(plural)
            <<~MD.chomp
              - `/#{plural}` — list all #{plural}
              - `/new <title>` — create a new #{singular}
              - `/delete <id>` — delete a #{singular}
            MD
          end.join("\n")

          write_file("README.md", <<~MD)
            # Telegram Bot

            Generated by Whoosh ClientGen.

            ## Setup

            1. Copy `.env` and fill in your `BOT_TOKEN`
            2. Run `bundle install`
            3. Run `ruby bot.rb`

            ## Commands

            - `/start` — show welcome message
            - `/login <email> <password>` — log in
            - `/register <name> <email> <password>` — create account
            - `/logout` — log out
            #{resource_commands}

            ## API

            Base URL: `#{ir.base_url}`
          MD
        end
      end
    end
  end
end
