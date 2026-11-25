require_relative "test_helper"

class SchemaTest < Minitest::Test
  class Address < Whoosh::Schema
    required :city, :string, max_length: 50
    optional :postal_code, :string, format: /\A\d{5}\z/
  end

  class Signup < Whoosh::Schema
    required :email, :email
    required :age, :integer, min: 17
    optional :newsletter, :boolean, default: false
    optional :plan, :string, enum: %w[free pro], default: "free"
    optional :address, Address
    optional :tags, :array, of: :string, max_items: 3
    optional :born_on, :date
    optional :balance, :decimal
    optional :nickname, :string, nullable: true
    optional :lines, :array do
      required :sku, :string
      required :qty, :integer, min: 1
    end
  end

  def test_coerces_and_defaults
    result = Signup.parse("email" => " Budi@Example.COM ", "age" => "30", "born_on" => "1995-04-02", "balance" => "10.25")
    assert_equal "budi@example.com", result[:email]
    assert_equal 30, result[:age]
    assert_equal false, result[:newsletter]
    assert_equal "free", result[:plan]
    assert_equal Date.new(1995, 4, 2), result[:born_on]
    assert_equal BigDecimal("10.25"), result[:balance]
    refute result.key?(:nickname)
    assert result.frozen?
  end

  def test_collects_nested_errors_with_paths
    error = assert_raises(Whoosh::ValidationError) do
      Signup.parse("email" => "nope", "age" => 12, "plan" => "gold",
                   "address" => { "postal_code" => "12" },
                   "lines" => [{ "sku" => "A", "qty" => 0 }, { "qty" => "x" }],
                   "tags" => %w[a b c d])
    end
    e = error.errors
    assert_equal ["must be an email address"], e["email"]
    assert_equal ["must be at least 17"], e["age"]
    assert_equal ["must be one of: free, pro"], e["plan"]
    assert_equal ["is required"], e["address.city"]
    assert_equal ["has an invalid format"], e["address.postal_code"]
    assert_equal ["must be at least 1"], e["lines[0].qty"]
    assert_equal ["is required"], e["lines[1].sku"]
    assert_equal ["must be a whole number"], e["lines[1].qty"]
    assert_equal ["must have at most 3 items"], e["tags"]
  end

  def test_nulls
    assert_nil Signup.parse("email" => "a@b.co", "age" => 20, "nickname" => nil)[:nickname]
    error = assert_raises(Whoosh::ValidationError) { Signup.parse("email" => nil, "age" => 20) }
    assert_equal ["is required"], error.errors["email"]
  end

  def test_rejects_wrong_types_strictly
    error = assert_raises(Whoosh::ValidationError) do
      Signup.parse("email" => "a@b.co", "age" => 20.5, "newsletter" => "maybe", "address" => "Jakarta", "tags" => "a")
    end
    assert_equal ["must be a whole number"], error.errors["age"]
    assert_equal ["must be true or false"], error.errors["newsletter"]
    assert_equal ["must be an object"], error.errors["address"]
    assert_equal ["must be a list"], error.errors["tags"]
  end

  def test_string_length_cap_by_default
    error = assert_raises(Whoosh::ValidationError) { Address.parse("city" => "x" * 60) }
    assert_equal ["must be at most 50 characters"], error.errors["city"]
    long = Class.new(Whoosh::Schema) { field :bio, :string }
    assert_raises(Whoosh::ValidationError) { long.parse("bio" => "x" * 10_001) }
  end

  def test_reject_unknown
    strict = Class.new(Whoosh::Schema) do
      reject_unknown!
      field :name, :string
    end
    error = assert_raises(Whoosh::ValidationError) { strict.parse("name" => "a", "role" => "admin") }
    assert_equal ["is not allowed"], error.errors["role"]
  end

  def test_dump_only_declared_fields_with_from
    schema = Class.new(Whoosh::Schema) do
      field :id, :integer
      field :total, :decimal
      field :placed_at, :datetime, from: :created_at
      field :customer_name, :string, from: ->(o) { o.customer.name }
      field :items, :array, of: :integer
    end
    order = Order.new(id: 1, total: BigDecimal("99.90"), secret: "x", created_at: Time.utc(2026, 1, 2, 3, 4, 5),
                      customer: Customer.new(id: 1, name: "Sari"))
    def order.items = [1, 2]
    out = schema.dump(order)
    assert_equal({ "id" => 1, "total" => "99.9", "placed_at" => "2026-01-02T03:04:05.000Z", "customer_name" => "Sari",
                   "items" => [1, 2] }, out)
  end

  def test_dump_hashes
    assert_equal({ "id" => 5, "name" => "Ani" }, CustomerSchema.dump({ id: 5, name: "Ani", password: "x" }))
  end

  def test_json_schema
    json = Signup.to_json_schema
    assert_equal %w[email age], json["required"]
    assert_equal({ "type" => "string", "format" => "email" }, json["properties"]["email"])
    assert_equal %w[free pro], json["properties"]["plan"]["enum"]
    assert_equal %w[string null], json["properties"]["nickname"]["type"]
    assert_equal "array", json["properties"]["lines"]["type"]
  end
end
