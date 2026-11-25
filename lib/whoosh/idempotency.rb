module Whoosh
  # Idempotency keys for unsafe endpoints (payments, orders). The first
  # request with a key runs; repeats with the same key and body get the
  # stored response; the same key with a different body is rejected.
  class Idempotency
    HEADER = "idempotency-key"
    KEY_FORMAT = /\A[\w\-.:]{8,255}\z/
    # How long a running request holds its key. If the process dies, retries
    # work again after this instead of after the full TTL.
    # ponytail: fixed 60 s, so a handler slower than that can run twice; make it configurable if one ever is.
    LOCK_TTL = 60

    def initialize(store, ttl:)
      @store = store
      @ttl = ttl
    end

    # Yields when the request should run. Returns a Rack triplet: either the
    # replayed response or the one the block produced.
    def call(request, scope:, client:, required:)
      key = request.header(HEADER)
      if key.nil? || key.empty?
        raise BadRequest.new("Send an Idempotency-Key header with this request.", code: "idempotency_key_missing") if required

        return yield
      end
      raise BadRequest.new("The Idempotency-Key header is invalid.", code: "idempotency_key_invalid") unless key.match?(KEY_FORMAT)

      store_key = "idem:#{scope}:#{client}:#{Digest::SHA256.hexdigest(key)}"
      fingerprint = Digest::SHA256.hexdigest("#{request.request_method} #{request.path}\n#{request.raw_body}")

      existing = @store.read(store_key)
      return replay(existing, fingerprint) if existing

      unless @store.write_unless_exists(store_key, { "state" => "processing", "fingerprint" => fingerprint }, ttl: [LOCK_TTL, @ttl].min)
        return replay(@store.read(store_key), fingerprint)
      end

      begin
        status, headers, body = yield
      rescue StandardError
        @store.delete(store_key)
        raise
      end

      if status >= 500
        @store.delete(store_key)
      else
        @store.write(store_key, { "state" => "done", "fingerprint" => fingerprint,
                                  "status" => status, "headers" => headers.slice("content-type", "location"),
                                  "body" => body.join }, ttl: @ttl)
      end
      [status, headers, body]
    end

    private

    def replay(record, fingerprint)
      raise Conflict.new("A request with this Idempotency-Key is still being processed.", code: "idempotency_in_progress") if record.nil? || record["state"] == "processing"

      if record["fingerprint"] != fingerprint
        raise UnprocessableEntity.new("This Idempotency-Key was already used with a different request.",
                                      code: "idempotency_key_reused")
      end

      headers = record["headers"].merge("idempotent-replayed" => "true")
      [record["status"], headers, [record["body"]]]
    end
  end
end
