# Whoosh Pagination & Metrics Design

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Offset and cursor pagination helpers, Prometheus metrics endpoint

## Pagination

### Offset-Based

```ruby
app.get "/users" do |req|
  page = (req.query_params["page"] || 1).to_i
  per_page = (req.query_params["per_page"] || 20).to_i
  paginate(db[:users].order(:id), page: page, per_page: per_page)
end
```

Returns:
```json
{
  "data": [...],
  "pagination": { "page": 1, "per_page": 20, "total": 150, "total_pages": 8 }
}
```

Implementation: `dataset.limit(per_page).offset((page - 1) * per_page)`. Count via `dataset.count`. Works with Sequel datasets or plain Arrays.

### Cursor-Based

```ruby
app.get "/messages" do |req|
  cursor = req.query_params["cursor"]
  limit = (req.query_params["limit"] || 20).to_i
  paginate_cursor(db[:messages].order(:id), cursor: cursor, limit: limit, column: :id)
end
```

Returns:
```json
{
  "data": [...],
  "pagination": { "next_cursor": "MjM=", "has_more": true, "limit": 20 }
}
```

Implementation: Decode cursor (Base64 → column value), `WHERE column > value LIMIT limit + 1`. If result has `limit + 1` rows, `has_more = true` and last row becomes `next_cursor`. Works with Sequel datasets or sorted Arrays.

### Array Support

For non-database collections, both helpers work with plain Arrays:
- Offset: `array.slice(offset, per_page)`, total = `array.size`
- Cursor: filter by comparing values, slice by limit

### Methods

Available in endpoints via `instance_exec` (same as `stream`, `cache`, etc.):
- `paginate(collection, page:, per_page:)` — offset-based
- `paginate_cursor(collection, cursor:, limit:, column: :id)` — cursor-based

## Metrics

### Auto-Tracked Metrics

Tracked automatically by middleware — no user code needed:

```
whoosh_requests_total{method="GET",path="/health",status="200"} 1234
whoosh_request_duration_seconds_sum{path="/health"} 45.23
whoosh_request_duration_seconds_count{path="/health"} 1234
```

### Custom Metrics

```ruby
app.get "/chat" do |req, metrics:|
  metrics.increment("chat_requests_total", labels: { model: "claude" })
  { reply: "hello" }
end
```

### Metrics Collector Interface

```ruby
metrics.increment("name", labels: {})      # counter += 1
metrics.gauge("name", value, labels: {})    # set to value
metrics.observe("name", value, labels: {})  # sum += value, count += 1
```

### /metrics Endpoint

Auto-registered at boot (like `/healthz`). Returns Prometheus text format:

```
# TYPE whoosh_requests_total counter
whoosh_requests_total{method="GET",path="/health",status="200"} 1234
# TYPE whoosh_request_duration_seconds summary
whoosh_request_duration_seconds_sum{path="/health"} 45.23
whoosh_request_duration_seconds_count{path="/health"} 1234
```

### Storage

In-memory `Hash` protected by `Mutex`. Thread-safe. Lost on restart (metrics are ephemeral by design — Prometheus scrapes frequently).

### Middleware Integration

`RequestLogger` middleware (already runs on every request) also records metrics — increment request counter and observe duration. No separate middleware needed.

## Files

### New Files

| File | Purpose |
|------|---------|
| `lib/whoosh/paginate.rb` | Pagination helpers (offset + cursor) |
| `lib/whoosh/metrics.rb` | Metrics collector with Prometheus output |
| `spec/whoosh/paginate_spec.rb` | Pagination tests |
| `spec/whoosh/metrics_spec.rb` | Metrics tests |
| `spec/whoosh/app_metrics_spec.rb` | App integration (auto-tracking + /metrics) |

### Modified Files

| File | Change |
|------|--------|
| `lib/whoosh.rb` | Add autoloads for Paginate, Metrics |
| `lib/whoosh/app.rb` | Add paginate/paginate_cursor methods, register metrics, add /metrics route |
| `lib/whoosh/middleware/request_logger.rb` | Record metrics on each request |
