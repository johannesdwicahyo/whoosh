require_relative "test_helper"

class RegressionTest < Minitest::Test
  include WhooshTestHelpers

  Event = Struct.new(:id, :created_at)

  # Rows created within the same second must not be skipped or repeated.
  def test_cursor_pagination_on_sub_second_timestamps
    base = Time.utc(2026, 1, 2, 3, 4, 5)
    events = (1..5).map { |i| Event.new(i, base + Rational(i, 1_000_000)) }
    pagination = Whoosh::Pagination.new(:cursor, by: :created_at, order: :desc)

    seen = []
    cursor = nil
    loop do
      page = pagination.call(events, { "limit" => "2", "cursor" => cursor }, Whoosh.config)
      seen.concat(page.records.map(&:id))
      cursor = page.meta["next_cursor"]
      break unless cursor
    end
    assert_equal [5, 4, 3, 2, 1], seen
  end

  # A request that dies mid-flight must not hold its key for the full TTL.
  def test_idempotency_key_of_a_crashed_request_is_released
    now = 0.0
    store = Whoosh::Stores::Memory.new(clock: -> { now })
    idempotency = Whoosh::Idempotency.new(store, ttl: 86_400)
    call = lambda do |&block|
      request = Whoosh::Request.new(env_for(:post, "/pay", body: {}, headers: { "idempotency-key" => "pay-key-0001" }))
      idempotency.call(request, scope: "POST /pay", client: "user:1", required: true, &block)
    end

    assert_raises(Interrupt) { call.call { raise Interrupt } } # process killed: no cleanup runs
    assert_raises(Whoosh::Conflict) { call.call { flunk "must not run while locked" } }

    now += Whoosh::Idempotency::LOCK_TTL + 1
    assert_equal 201, call.call { [201, {}, ["{}"]] }.first

    now += 3600 # finished responses are still kept for the full TTL
    status, headers, = call.call { flunk "must replay" }
    assert_equal [201, "true"], [status, headers["idempotent-replayed"]]
  end

  class PingAPI < Whoosh::API
    get "/ping" do
      public!
      returns { field :pong, :boolean }
      handle { { pong: true } }
    end
  end

  def test_each_request_logs_one_line_without_the_query_string
    lines = []
    logger = Object.new
    logger.define_singleton_method(:info) { |&block| lines << block.call }
    Whoosh.reset_config!
    Whoosh.config.logger = logger

    PingAPI.call(env_for(:get, "/ping", query: "token=secret").merge("SCRIPT_NAME" => "/api"))
    PingAPI.call(env_for(:get, "/missing"))

    assert_equal 2, lines.size
    assert_match(%r{\A\[whoosh\] GET /api/ping 200 in \d+\.\d+ms request_id=[\w-]+\z}, lines[0])
    assert_match(%r{\A\[whoosh\] GET /missing 404 in }, lines[1])
    refute_includes lines[0], "secret"
  ensure
    Whoosh.reset_config!
  end

  def test_decimal_scale_pads_output_and_limits_input
    schema = Class.new(Whoosh::Schema) do
      field :price, :decimal, scale: 2
      field :units, :decimal, scale: 0
      field :rates, :array, of: :decimal, scale: 3
    end

    out = schema.dump({ price: BigDecimal("2000.5"), units: BigDecimal("3"), rates: [BigDecimal("0.1"), 2] })
    assert_equal({ "price" => "2000.50", "units" => "3", "rates" => ["0.100", "2.000"] }, out)
    assert_equal "0.00", schema.dump({ price: BigDecimal("-0.001") })["price"]
    assert_equal "123456789012345678.90", schema.dump({ price: BigDecimal("123456789012345678.9") })["price"]

    assert_equal BigDecimal("12.5"), schema.parse({ "price" => "12.50" })[:price]
    error = assert_raises(Whoosh::ValidationError) { schema.parse({ "price" => "12.505" }) }
    assert_match(/at most 2 decimal places/, error.errors.to_s)

    assert_raises(Whoosh::DefinitionError) { Class.new(Whoosh::Schema) { field :name, :string, scale: 2 } }
  end

  def test_api_sign_in_skips_tokens_until_reset
    require "whoosh/test_helpers"
    extend Whoosh::TestHelpers
    api = Class.new(Whoosh::API) do
      get "/me" do
        authorize { true }
        returns { field :name, :string }
        handle { { name: current_user } }
      end
    end

    assert_equal 401, api.call(env_for(:get, "/me"))[0]
    api_sign_in "sari"
    status, _, body = api.call(env_for(:get, "/me"))
    assert_equal 200, status
    assert_includes body.join, "sari"
    api_sign_in nil
    assert_equal 401, api.call(env_for(:get, "/me"))[0]

    api_sign_in "sari"
    Whoosh::TestHelpers.reset!
    assert_equal 401, api.call(env_for(:get, "/me"))[0]
  ensure
    Whoosh::TestHelpers.reset!
  end

  def test_generated_schema_fields_leave_out_credentials_and_unknown_types
    require "generators/whoosh/api/fields"
    column = Struct.new(:name, :type, :scale)
    lines, skipped = Whoosh::Generators::Fields.from([
      column.new("id", :integer), column.new("price", :decimal, 2), column.new("rate", :decimal),
      column.new("meta", :jsonb), column.new("password_digest", :string), column.new("location", :point),
      column.new("created_at", :datetime), column.new("role", :integer)
    ], enums: ["role"])
    assert_equal ["field :id, :integer", "field :price, :decimal, scale: 2", "field :rate, :decimal",
                  "field :meta, :json", "field :created_at, :datetime", "field :role, :string"], lines
    assert_equal %w[password_digest location], skipped
  end

  class StrictAPI < Whoosh::API
    get "/things/:id" do
      authorize { true }
      params { required :id, :integer }
      returns { field :id, :integer }
      handle { |p| p[:id] == 402 ? error!(402, "payment_required", "Top up first.") : { id: p[:id] } }
    end
  end

  def test_problem_json_error_format
    Whoosh.reset_config!
    Whoosh.config.error_format = :problem
    Whoosh.config.authenticate = ->(req) { req.bearer_token }
    Whoosh.config.openapi = true

    status, headers, body = StrictAPI.call(env_for(:get, "/things/1"))
    assert_equal 401, status
    assert_equal "application/problem+json; charset=utf-8", headers["content-type"]
    assert_equal({ "type" => "about:blank", "title" => "Unauthorized", "status" => 401,
                   "detail" => "Sign in or send a valid token.", "code" => "unauthorized",
                   "request_id" => headers["x-request-id"] }, JSON.parse(body.join))

    status, _, body = StrictAPI.call(env_for(:get, "/things/abc", token: "t"))
    problem = JSON.parse(body.join)
    assert_equal 422, status
    assert_equal "Unprocessable Content", problem["title"]
    assert_equal({ "id" => ["must be a whole number"] }, problem["errors"])
    refute problem.key?("error")

    status, _, body = StrictAPI.call(env_for(:get, "/things/402", token: "t"))
    assert_equal [402, "Payment Required", "payment_required"], [status, *JSON.parse(body.join).values_at("title", "code")]

    # Success bodies and their content type are untouched.
    status, headers, body = StrictAPI.call(env_for(:get, "/things/7", token: "t"))
    assert_equal [200, "application/json; charset=utf-8", { "data" => { "id" => 7 } }],
                 [status, headers["content-type"], JSON.parse(body.join)]

    doc = JSON.parse(StrictAPI.call(env_for(:get, "/openapi.json"))[2].join)
    assert_equal %w[type title status detail code request_id], doc.dig("components", "schemas", "Error", "required")
    assert doc.dig("paths", "/things/{id}", "get", "responses", "401", "content", "application/problem+json")

    assert_raises(ArgumentError) { Whoosh.config.error_format = :xml }
  ensure
    Whoosh.reset_config!
  end

  class ConflictAPI < Whoosh::API
    get "/orders/:id" do
      public!
      returns { field :id, :integer }
      handle do |p|
        conflict!("Changed since you loaded it", extra: { order: { "id" => 7, "status" => "paid" }, status: 200, request_id: "forged" }) if p[:id] == "7"
        error!(402, "payment_required", "Top up first.", extra: { "balance" => 0 }) if p[:id] == "8"
        { id: 1 }
      end
    end
  end

  def test_errors_can_carry_extra_data
    Whoosh.reset_config!
    status, headers, body = ConflictAPI.call(env_for(:get, "/orders/7"))
    error = JSON.parse(body.join).fetch("error")
    assert_equal 409, status
    assert_equal({ "id" => 7, "status" => "paid" }, error.dig("extra", "order"))
    assert_equal headers["x-request-id"], error["request_id"]

    Whoosh.config.error_format = :problem
    status, headers, body = ConflictAPI.call(env_for(:get, "/orders/7"))
    problem = JSON.parse(body.join)
    assert_equal({ "id" => 7, "status" => "paid" }, problem["order"])
    # extra can add members but never replace the ones Whoosh sets
    assert_equal [409, 409, "Conflict", headers["x-request-id"]], [status, problem["status"], problem["title"], problem["request_id"]]

    _, _, body = ConflictAPI.call(env_for(:get, "/orders/8"))
    assert_equal [402, 0], JSON.parse(body.join).values_at("status", "balance")
    _, _, body = ConflictAPI.call(env_for(:get, "/orders/9"))
    assert_equal({ "data" => { "id" => 1 } }, JSON.parse(body.join))
  ensure
    Whoosh.reset_config!
  end
end
