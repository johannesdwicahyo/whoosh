require_relative "test_helper"

class DefinitionTest < Minitest::Test
  include WhooshTestHelpers

  def setup = configure_whoosh!

  def define(&block)
    Class.new(Whoosh::API, &block)
  end

  def test_endpoint_without_access_rule_fails_at_definition
    error = assert_raises(Whoosh::DefinitionError) do
      define do
        get "/leaky" do
          returns OrderSchema
          handle { [] }
        end
      end
    end
    assert_match(/no access rule/, error.message)
  end

  def test_endpoint_without_returns_fails
    error = assert_raises(Whoosh::DefinitionError) do
      define do
        get "/x" do
          public!
          handle { {} }
        end
      end
    end
    assert_match(/doesn't declare its response/, error.message)
  end

  def test_endpoint_without_handler_fails
    assert_raises(Whoosh::DefinitionError) do
      define do
        get "/x" do
          public!
          returns nil
        end
      end
    end
  end

  def test_duplicate_route_and_conflicting_params_fail
    assert_raises(Whoosh::DefinitionError) do
      define do
        2.times do
          get "/x" do
            public!
            returns nil
            handle {}
          end
        end
      end
    end
    assert_raises(Whoosh::DefinitionError) do
      api = define do
        get "/a/:id" do
          public!
          returns nil
          handle {}
        end
        get "/a/:slug/b" do
          public!
          returns nil
          handle {}
        end
      end
      api.call(env_for(:get, "/a/1"))
    end
  end

  def test_version_after_endpoints_fails
    assert_raises(Whoosh::DefinitionError) do
      define do
        get "/x" do
          public!
          returns nil
          handle {}
        end
        version 2
      end
    end
  end

  def test_free_form_objects_must_be_explicit
    assert_raises(Whoosh::DefinitionError) { Class.new(Whoosh::Schema) { field :meta, :object } }
    assert_raises(Whoosh::DefinitionError) { Class.new(Whoosh::Schema) { field :tags, :array } }
    assert_raises(Whoosh::DefinitionError) { Class.new(Whoosh::Schema) { field :x, :strng } }
    assert_raises(Whoosh::DefinitionError) { Class.new(Whoosh::Schema) { field :x, :string, maxlength: 3 } }
  end

  def test_undeclared_path_params_are_still_passed_as_strings
    api = define do
      get "/stores/:store_id/ping" do
        public!
        returns { field :store, :string }
        handle { |p| { store: p[:store_id] } }
      end
    end
    _, _, body = request(api, :get, "/stores/st%20ore/ping")
    assert_equal "st ore", body.dig("data", "store")
  end

  def test_helpers_inherited_and_rescue_from
    stock_error = Class.new(StandardError)
    base = define do
      version 2
      helpers { def shout(s) = s.upcase }
      rescue_from(stock_error) { |e| Whoosh::Conflict.new(e.message, code: "out_of_stock") }
    end
    api = Class.new(base) do
      get "/hi" do
        public!
        returns { field :msg, :string }
        handle { { msg: shout("hi") } }
      end
      post "/buy" do
        public!
        returns nil
        handle { raise stock_error, "Only 2 left" }
      end
    end
    _, _, body = request(api, :get, "/v2/hi")
    assert_equal "HI", body.dig("data", "msg")
    status, _, body = request(api, :post, "/v2/buy")
    assert_equal 409, status
    assert_equal({ "code" => "out_of_stock", "message" => "Only 2 left" }, body["error"].slice("code", "message"))
  end

  def test_context_helpers_for_errors
    api = define do
      post "/pay" do
        public!
        params { required :amount, :integer }
        returns nil
        handle do |p|
          invalid!(amount: "exceeds your balance") if p[:amount] > 100
          error!(402, "payment_required", "Top up first.")
        end
      end
    end
    status, _, body = request(api, :post, "/pay", body: { amount: 500 })
    assert_equal 422, status
    assert_equal({ "amount" => ["exceeds your balance"] }, body.dig("error", "details"))
    status, _, body = request(api, :post, "/pay", body: { amount: 5 })
    assert_equal 402, status
    assert_equal "payment_required", body.dig("error", "code")
  end

  def test_active_record_errors_are_translated_by_name
    mod = Module.new
    Object.const_set(:ActiveRecord, mod) unless defined?(::ActiveRecord)
    ::ActiveRecord.const_set(:RecordNotFound, Class.new(StandardError)) unless defined?(::ActiveRecord::RecordNotFound)
    api = define do
      get "/r" do
        public!
        returns nil
        handle { raise ::ActiveRecord::RecordNotFound }
      end
    end
    assert_equal 404, request(api, :get, "/r").first
  end

  def test_required_idempotency_key
    api = define do
      post "/charge" do
        public!
        idempotent required: true
        returns nil
        handle {}
      end
    end
    status, _, body = request(api, :post, "/charge")
    assert_equal 400, status
    assert_equal "idempotency_key_missing", body.dig("error", "code")
    assert_equal 204, request(api, :post, "/charge", headers: { "idempotency-key" => "charge-0001" }).first
  end
end
