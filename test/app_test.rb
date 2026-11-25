require_relative "test_helper"

class AppTest < Minitest::Test
  include WhooshTestHelpers

  ORDERS = (1..7).map do |i|
    Order.new(id: i, number: "INV-#{i}", total: BigDecimal("1250.50") * i, status: i.even? ? "paid" : "pending",
              secret: "do-not-leak", customer: Customer.new(id: 9, name: "Budi"))
  end

  class OrdersAPI < Whoosh::API
    version 1

    helpers do
      def visible_orders = AppTest::ORDERS
    end

    get "/orders" do
      authorize { |user| user.admin? || user.role == :staff }
      params { optional :status, :string, enum: %w[pending paid] }
      paginate
      returns OrderSchema
      handle { |p| p[:status] ? visible_orders.select { |o| o.status == p[:status] } : visible_orders }
    end

    get "/orders/stats" do
      authorize { |user| user.admin? }
      returns { field :count, :integer }
      handle { { count: visible_orders.size } }
    end

    get "/orders/:id" do
      authorize { true }
      params { required :id, :integer, min: 1 }
      returns OrderSchema
      handle { |p| visible_orders.find { |o| o.id == p[:id] } }
    end

    post "/orders" do
      authorize { |user| user.admin? }
      idempotent
      params do
        required :number, :string, max_length: 20
        required :total, :decimal, min: 0
        optional :items, :array, of: :integer, max_items: 3
        optional :note, :string, nullable: true
      end
      returns OrderSchema
      handle do |p|
        header "location", "/v1/orders/99"
        Order.new(id: 99, number: p[:number], total: p[:total], status: "pending", secret: "x")
      end
    end

    delete "/orders/:id" do
      authorize { |user| user.admin? }
      returns nil
      handle { |_| :ok }
    end

    get "/boom" do
      public!
      returns { field :ok, :boolean }
      handle { raise "database password is hunter2" }
    end

    get "/ping" do
      public!
      returns { field :pong, :boolean }
      handle { { pong: true } }
    end
  end

  def setup
    configure_whoosh!
  end

  def app = OrdersAPI

  # ---- routing --------------------------------------------------------------

  def test_versioned_routes_static_beats_param
    assert_equal [%w[GET /v1/orders], %w[GET /v1/orders/stats], %w[GET /v1/orders/:id], %w[POST /v1/orders],
                  %w[DELETE /v1/orders/:id], %w[GET /v1/boom], %w[GET /v1/ping]], app.routes
    status, _, body = request(app, :get, "/v1/orders/stats", token: "admin-token")
    assert_equal 200, status
    assert_equal({ "data" => { "count" => 7 } }, body)
  end

  def test_unknown_route_is_404_envelope_with_request_id
    status, headers, body = request(app, :get, "/v1/nope", token: "admin-token")
    assert_equal 404, status
    assert_equal "not_found", body.dig("error", "code")
    assert_equal headers["x-request-id"], body.dig("error", "request_id")
  end

  def test_wrong_method_is_405_with_allow
    status, headers, body = request(app, :put, "/v1/orders/1", token: "admin-token")
    assert_equal 405, status
    assert_equal "method_not_allowed", body.dig("error", "code")
    assert_includes headers["allow"], "DELETE"
  end

  def test_trailing_slash_and_head
    status, = request(app, :get, "/v1/ping/")
    assert_equal 200, status
    status, headers, body = request(app, :head, "/v1/ping")
    assert_equal 200, status
    assert_nil body
    assert_equal "{\"data\":{\"pong\":true}}".bytesize.to_s, headers["content-length"]
  end

  # ---- authentication & authorization ---------------------------------------

  def test_anonymous_gets_401_on_private_endpoints
    status, _, body = request(app, :get, "/v1/orders")
    assert_equal 401, status
    assert_equal "unauthorized", body.dig("error", "code")
  end

  def test_authorize_false_is_403
    status, _, body = request(app, :get, "/v1/orders/stats", token: "staff-token")
    assert_equal 403, status
    assert_equal "forbidden", body.dig("error", "code")
  end

  def test_public_endpoint_needs_no_user
    status, _, body = request(app, :get, "/v1/ping")
    assert_equal 200, status
    assert_equal({ "data" => { "pong" => true } }, body)
  end

  # ---- params ----------------------------------------------------------------

  def test_path_param_coerced_and_validated
    status, _, body = request(app, :get, "/v1/orders/3", token: "staff-token")
    assert_equal 200, status
    assert_equal 3, body.dig("data", "id")

    status, _, body = request(app, :get, "/v1/orders/abc", token: "staff-token")
    assert_equal 422, status
    assert_equal({ "id" => ["must be a whole number"] }, body.dig("error", "details"))
  end

  def test_missing_record_is_404
    status, _, body = request(app, :get, "/v1/orders/404", token: "staff-token")
    assert_equal 404, status
    assert_equal "not_found", body.dig("error", "code")
  end

  def test_body_validation_collects_all_errors
    status, _, body = request(app, :post, "/v1/orders", token: "admin-token",
                                                         body: { total: "-5", items: [1, "x", 3, 4], note: nil })
    assert_equal 422, status
    details = body.dig("error", "details")
    assert_equal ["is required"], details["number"]
    assert_equal ["must be at least 0"], details["total"]
    assert_equal ["must have at most 3 items"], details["items"]
  end

  def test_unknown_keys_never_reach_the_handler_and_output_is_filtered
    status, headers, body = request(app, :post, "/v1/orders", token: "admin-token",
                                                                body: { number: "INV-99", total: "10.5", admin: true, secret: "inject" })
    assert_equal 201, status
    assert_equal "/v1/orders/99", headers["location"]
    assert_equal({ "id" => 99, "number" => "INV-99", "total" => "10.5", "status" => "pending", "customer" => nil }, body["data"])
    refute_includes JSON.generate(body), "secret"
  end

  def test_query_enum
    status, _, body = request(app, :get, "/v1/orders", token: "staff-token", query: { status: "paid" })
    assert_equal 200, status
    assert(body["data"].all? { |o| o["status"] == "paid" })

    status, _, body = request(app, :get, "/v1/orders", token: "staff-token", query: { status: "refunded" })
    assert_equal 422, status
    assert_match(/must be one of/, body.dig("error", "details", "status").first)
  end

  def test_rejects_non_json_bodies_and_malformed_json
    status, _, body = request(app, :post, "/v1/orders", token: "admin-token", body: "number=1",
                                                         headers: { "content-type" => "application/x-www-form-urlencoded" })
    assert_equal 415, status
    assert_equal "unsupported_media_type", body.dig("error", "code")

    status, _, body = request(app, :post, "/v1/orders", token: "admin-token", body: "{\"number\":")
    assert_equal 400, status
    assert_equal "The JSON body is malformed.", body.dig("error", "message")

    status, = request(app, :post, "/v1/orders", token: "admin-token", body: "[1,2]")
    assert_equal 400, status
  end

  def test_body_size_limit
    Whoosh.config.max_body_size = 100
    status, _, body = request(app, :post, "/v1/orders", token: "admin-token", body: { number: "x" * 200, total: 1 })
    assert_equal 413, status
    assert_equal "payload_too_large", body.dig("error", "code")
  end

  def test_json_depth_limit
    deep = "#{'{"a":' * 30}1#{'}' * 30}"
    status, _, body = request(app, :post, "/v1/orders", token: "admin-token", body: deep)
    assert_equal 400, status
    assert_match(/nested too deeply/, body.dig("error", "message"))
  end

  # ---- responses -------------------------------------------------------------

  def test_delete_returns_204_without_body
    status, headers, body = request(app, :delete, "/v1/orders/1", token: "admin-token")
    assert_equal 204, status
    assert_nil body
    assert_nil headers["content-type"]
  end

  def test_unexpected_errors_are_hidden
    status, _, body = request(app, :get, "/v1/boom")
    assert_equal 500, status
    assert_equal "internal_error", body.dig("error", "code")
    refute_includes JSON.generate(body), "hunter2"
  end

  def test_unexpected_errors_shown_when_exposed_and_reported
    reported = []
    Whoosh.config.expose_errors = true
    Whoosh.config.on_error = ->(e, _) { reported << e.message }
    _, _, body = request(app, :get, "/v1/boom")
    assert_includes body.dig("error", "message"), "hunter2"
    assert_equal ["database password is hunter2"], reported
  end

  def test_security_headers
    _, headers, = request(app, :get, "/v1/ping")
    assert_equal "nosniff", headers["x-content-type-options"]
    assert_equal "DENY", headers["x-frame-options"]
    assert_equal "no-store", headers["cache-control"]
    assert_equal "application/json; charset=utf-8", headers["content-type"]
    assert_nil headers["strict-transport-security"]

    _, headers, = app.call(env_for(:get, "/v1/ping").merge("rack.url_scheme" => "https"))
    assert_match(/max-age/, headers["strict-transport-security"])
  end

  def test_request_id_kept_when_safe
    _, headers, = request(app, :get, "/v1/ping", headers: { "x-request-id" => "abc-123" })
    assert_equal "abc-123", headers["x-request-id"]
    _, headers, = request(app, :get, "/v1/ping", headers: { "x-request-id" => "<script>" })
    refute_equal "<script>", headers["x-request-id"]
  end

  # ---- pagination ------------------------------------------------------------

  def test_cursor_pagination_walks_all_pages
    seen = []
    cursor = nil
    3.times do
      query = { limit: 3 }
      query[:cursor] = cursor if cursor
      status, _, body = request(app, :get, "/v1/orders", token: "staff-token", query: query)
      assert_equal 200, status
      seen.concat(body["data"].map { |o| o["id"] })
      cursor = body.dig("meta", "next_cursor")
      break unless cursor
    end
    assert_equal (1..7).to_a, seen
    assert_nil cursor
  end

  def test_page_size_and_cursor_validation
    status, _, body = request(app, :get, "/v1/orders", token: "staff-token", query: { limit: 1000 })
    assert_equal 422, status
    assert_equal ["must be between 1 and 100"], body.dig("error", "details", "limit")

    status, _, body = request(app, :get, "/v1/orders", token: "staff-token", query: { cursor: "!!garbage" })
    assert_equal 422, status
    assert_equal ["is invalid"], body.dig("error", "details", "cursor")
  end

  # ---- rate limiting ---------------------------------------------------------

  def test_rate_limit_per_client
    Whoosh.config.rate_limit = [2, 60]
    2.times { assert_equal 200, request(app, :get, "/v1/ping").first }
    status, headers, body = request(app, :get, "/v1/ping")
    assert_equal 429, status
    assert_equal "rate_limited", body.dig("error", "code")
    assert headers["retry-after"].to_i.positive?

    # A signed-in user has their own bucket.
    assert_equal 200, request(app, :get, "/v1/ping", token: "admin-token").first
  end

  def test_failed_logins_are_rate_limited_too
    Whoosh.config.rate_limit = [2, 60]
    2.times { assert_equal 401, request(app, :get, "/v1/orders", token: "wrong").first }
    assert_equal 429, request(app, :get, "/v1/orders", token: "wrong").first
  end

  # ---- idempotency -----------------------------------------------------------

  def test_idempotent_replay_and_reuse
    body = { number: "INV-1", total: "5" }
    h = { "idempotency-key" => "order-key-0001" }
    s1, h1, b1 = request(app, :post, "/v1/orders", token: "admin-token", body: body, headers: h)
    s2, h2, b2 = request(app, :post, "/v1/orders", token: "admin-token", body: body, headers: h)
    assert_equal [201, 201], [s1, s2]
    assert_equal b1, b2
    assert_nil h1["idempotent-replayed"]
    assert_equal "true", h2["idempotent-replayed"]

    status, _, err = request(app, :post, "/v1/orders", token: "admin-token", body: body.merge(total: "6"), headers: h)
    assert_equal 422, status
    assert_equal "idempotency_key_reused", err.dig("error", "code")

    status, _, err = request(app, :post, "/v1/orders", token: "admin-token", body: body, headers: { "idempotency-key" => "x" })
    assert_equal 400, status
    assert_equal "idempotency_key_invalid", err.dig("error", "code")
  end

  # ---- CORS ------------------------------------------------------------------

  def test_cors_closed_by_default
    _, headers, = request(app, :get, "/v1/ping", headers: { "origin" => "https://evil.example" })
    assert_nil headers["access-control-allow-origin"]
  end

  def test_cors_allowed_origin_and_preflight
    Whoosh.config.cors_origins = ["https://app.example.com"]
    _, headers, = request(app, :get, "/v1/ping", headers: { "origin" => "https://app.example.com" })
    assert_equal "https://app.example.com", headers["access-control-allow-origin"]
    assert_equal "origin", headers["vary"]

    status, headers, = request(app, :options, "/v1/orders/1", headers: {
                                 "origin" => "https://app.example.com",
                                 "access-control-request-method" => "DELETE",
                                 "access-control-request-headers" => "Authorization, Content-Type, X-Evil"
                               })
    assert_equal 204, status
    assert_equal "GET, DELETE, HEAD", headers["access-control-allow-methods"]
    assert_equal "authorization, content-type", headers["access-control-allow-headers"]

    _, headers, = request(app, :options, "/v1/orders/1", headers: {
                            "origin" => "https://evil.example", "access-control-request-method" => "DELETE"
                          })
    assert_nil headers["access-control-allow-methods"]
  end

  # ---- composition -----------------------------------------------------------

  def test_combined_app_and_lazy_app
    combined = Whoosh.app(OrdersAPI)
    assert_equal 200, request(combined, :get, "/v1/ping").first
    lazy = Whoosh.app("AppTest::OrdersAPI")
    assert_equal 200, request(lazy, :get, "/v1/ping").first
  end
end
