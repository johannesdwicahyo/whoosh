$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "minitest/autorun"
require "stringio"
require "whoosh"

User = Struct.new(:id, :role, keyword_init: true) do
  def admin? = role == :admin
end

Order = Struct.new(:id, :number, :total, :status, :secret, :customer, :created_at, keyword_init: true)
Customer = Struct.new(:id, :name, keyword_init: true)

TOKENS = {
  "admin-token" => User.new(id: 1, role: :admin),
  "staff-token" => User.new(id: 2, role: :staff)
}.freeze

class CustomerSchema < Whoosh::Schema
  field :id, :integer
  field :name, :string
end

class OrderSchema < Whoosh::Schema
  field :id, :integer
  field :number, :string
  field :total, :decimal
  field :status, :string
  field :customer, CustomerSchema
end

module WhooshTestHelpers
  # Builds a Rack env without depending on the rack gem.
  def env_for(method, path, body: nil, headers: {}, token: nil, query: nil)
    raw = body.is_a?(String) ? body : (body && JSON.generate(body))
    env = {
      "REQUEST_METHOD" => method.to_s.upcase,
      "PATH_INFO" => path,
      "QUERY_STRING" => query.is_a?(Hash) ? URI.encode_www_form(query) : query.to_s,
      "SCRIPT_NAME" => "",
      "SERVER_NAME" => "example.org",
      "SERVER_PORT" => "80",
      "REMOTE_ADDR" => "203.0.113.7",
      "rack.url_scheme" => "http",
      "rack.input" => StringIO.new(raw.to_s)
    }
    if raw
      env["CONTENT_TYPE"] = "application/json"
      env["CONTENT_LENGTH"] = raw.bytesize.to_s
    end
    env["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    headers.each do |k, v|
      key = k.to_s.upcase.tr("-", "_")
      key = "HTTP_#{key}" unless %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
      env[key] = v
    end
    env
  end

  def request(app, method, path, **options)
    status, headers, body = app.call(env_for(method, path, **options))
    text = body.join
    parsed = text.empty? ? nil : JSON.parse(text)
    [status, headers, parsed]
  end

  def configure_whoosh!
    Whoosh.reset_config!
    Whoosh.configure do |c|
      c.authenticate = ->(req) { TOKENS[req.bearer_token] }
      c.rate_limit = nil
    end
  end
end
