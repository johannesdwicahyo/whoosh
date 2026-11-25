require_relative "test_helper"

class OpenAPITest < Minitest::Test
  include WhooshTestHelpers

  class ShopAPI < Whoosh::API
    version 1
    tag "Orders"
    openapi_info title: "Shop API", version: "1.2.0"

    get "/orders" do
      summary "List orders"
      authorize { true }
      params { optional :status, :string, enum: %w[pending paid] }
      paginate
      returns OrderSchema
      handle { [] }
    end

    patch "/orders/:id" do
      authorize { true }
      idempotent
      params do
        required :id, :integer
        optional :status, :string
      end
      returns OrderSchema
      handle { nil }
    end

    get "/health" do
      public!
      returns nil
      handle {}
    end
  end

  def setup = configure_whoosh!

  def test_document
    doc = ShopAPI.openapi
    assert_equal "3.1.0", doc["openapi"]
    assert_equal "Shop API", doc.dig("info", "title")
    assert_equal "1.2.0", doc.dig("info", "version")

    list = doc.dig("paths", "/v1/orders", "get")
    assert_equal "List orders", list["summary"]
    assert_equal ["Orders"], list["tags"]
    assert_equal %w[status limit cursor], list["parameters"].map { |p| p["name"] }
    data = list.dig("responses", "200", "content", "application/json", "schema", "properties", "data")
    assert_equal({ "type" => "array", "items" => { "$ref" => "#/components/schemas/OrderSchema" } }, data)
    assert_includes list["responses"].keys, "401"

    patch = doc.dig("paths", "/v1/orders/{id}", "patch")
    assert_equal({ "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } }, patch["parameters"][0])
    assert_equal "Idempotency-Key", patch["parameters"][1]["name"]
    assert_equal({ "status" => { "type" => "string" } }, patch.dig("requestBody", "content", "application/json", "schema", "properties"))

    assert_equal [], doc.dig("paths", "/v1/health", "get", "security")
    assert doc.dig("components", "schemas", "CustomerSchema")
    assert doc.dig("components", "schemas", "Error")
  end

  def test_served_only_when_enabled
    assert_equal 404, request(ShopAPI, :get, "/openapi.json").first
    Whoosh.config.openapi = :authenticated
    assert_equal 401, request(ShopAPI, :get, "/openapi.json").first
    Whoosh.config.openapi = true
    status, _, body = request(ShopAPI, :get, "/openapi.json")
    assert_equal 200, status
    assert_equal "3.1.0", body["openapi"]
  end
end
