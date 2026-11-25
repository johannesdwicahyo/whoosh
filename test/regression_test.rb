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
end
