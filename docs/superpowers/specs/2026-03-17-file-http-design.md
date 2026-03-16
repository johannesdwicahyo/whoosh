# Whoosh File Upload & HTTP Client Design

**Date:** 2026-03-17
**Status:** Approved
**Scope:** File upload with storage adapters, HTTP client wrapper

## Overview

Two components: file upload handling with local/S3 storage, and an HTTP client for calling external APIs. Both follow "zero deps, upgrade when ready."

## File Upload

### Request Integration

Rack parses multipart forms into `rack.request.form_hash`. We add `req.files` to `Whoosh::Request` that **filters** to only return entries with a `:tempfile` key (skipping plain form fields), wrapping each in `Whoosh::UploadedFile`.

```ruby
app.post "/upload" do |req|
  file = req.files["document"]

  file.filename      # => "report.pdf"
  file.content_type  # => "application/pdf" (mapped from Rack's :type key)
  file.size          # => 245760
  file.read          # => raw bytes
  file.read_text     # => UTF-8 string (for RAG pipelines)
  file.to_base64     # => base64 encoded (for vision LLM APIs)

  # Save via storage adapter (passed to UploadedFile at construction)
  path = file.save("documents")  # => "documents/abc123_report.pdf"
  { path: path, size: file.size }
end
```

### UploadedFile

Wraps Rack's `{ filename:, type:, tempfile: }` hash. Receives a storage adapter reference at construction time (injected by `req.files`).

- `filename` — original filename
- `content_type` — MIME type (mapped from Rack's `:type` key)
- `size` — file size in bytes via `tempfile.size`
- `read` — raw binary content (rewinds tempfile before reading)
- `read_text` — content as UTF-8 string. Returns the bytes with `force_encoding("UTF-8")`. For binary files (PDFs, images), prefer `read` or `to_base64` instead.
- `to_base64` — `Base64.strict_encode64(read)` for vision API payloads
- `save(prefix)` — delegates to the injected storage adapter: `@storage.save(self, prefix)`
- `validate!(types:, max_size:)` — raises `ValidationError` if MIME type not in list or size exceeds max. Also rejects blank filenames (empty upload).

**Thread safety:** `UploadedFile` instances are request-scoped (one per upload per request). Do not share across threads.

### Storage

```yaml
# config/app.yml
storage:
  adapter: local            # local | s3
  local_root: uploads/      # for local adapter
  s3_bucket: my-bucket      # for s3 adapter
  s3_region: us-east-1
  s3_access_key_id: <%= ENV["AWS_ACCESS_KEY_ID"] %>
  s3_secret_access_key: <%= ENV["AWS_SECRET_ACCESS_KEY"] %>
```

- **LocalStorage** — saves to `{local_root}/{prefix}/{uuid}_{filename}`. Creates directories via `FileUtils.mkdir_p`. Default adapter. IO errors (`Errno::ENOSPC`, `Errno::EACCES`) propagate to caller.
- **S3Storage** — uploads to `{bucket}/{prefix}/{uuid}_{filename}`. Requires `aws-sdk-s3` gem (lazy-loaded, raises `DependencyError` if missing). S3 SDK errors (`Aws::S3::Errors`) propagate to caller — no silent swallowing.
- **Storage.build(config)** — factory that creates the right adapter from config. Registered via DI as `storage` singleton.
- Files named with UUID prefix to avoid collisions.

### How UploadedFile Gets Storage

`Request#files` receives the storage adapter from `env["whoosh.storage"]` (set by App in `handle_request`, same pattern as `env["whoosh.logger"]`). Each `UploadedFile` is constructed with this reference:

```ruby
# In Request#files:
def files
  @files ||= begin
    storage = @env["whoosh.storage"]
    form_data = @rack_request.params
    form_data.each_with_object({}) do |(key, value), hash|
      next unless value.is_a?(Hash) && value[:tempfile]
      hash[key] = UploadedFile.new(value, storage: storage)
    end
  end
end
```

### Validation

```ruby
file.validate!(types: ["application/pdf", "image/png"], max_size: 10_000_000)
# Raises Whoosh::Errors::ValidationError with details:
# - "File type image/gif not allowed" if MIME mismatch
# - "File too large (5MB > 1MB)" if size exceeded
# - "No file uploaded" if filename is blank
```

## HTTP Client

### Interface

```ruby
Whoosh::HTTP.get(url, headers: {}, timeout: 30)
Whoosh::HTTP.post(url, json: nil, body: nil, headers: {}, timeout: 30)
Whoosh::HTTP.put(url, json: nil, body: nil, headers: {}, timeout: 30)
Whoosh::HTTP.patch(url, json: nil, body: nil, headers: {}, timeout: 30)
Whoosh::HTTP.delete(url, headers: {}, timeout: 30)
```

### HTTPS Support

The wrapper parses the URL and **automatically enables SSL** when the scheme is `https`. Uses `Net::HTTP.new(uri.host, uri.port)` with `http.use_ssl = (uri.scheme == "https")`. This is transparent — HTTPS URLs in the examples work without extra configuration.

### Response Object

```ruby
response.status      # => Integer (200, 404, etc.)
response.body        # => String (raw response body)
response.json        # => Hash (parsed JSON, raises JSON::ParserError on non-JSON)
response.headers     # => Hash (response headers)
response.ok?         # => true if status 200-299
```

### Engine Selection

- Default: `Net::HTTP` (stdlib, zero deps) with automatic HTTPS
- If `httpx` gem is present: uses HTTPX for HTTP/2, connection pooling, async support
- Detection at first use, same pattern as Oj/JSON
- Thread-safe: engine detection sets a class-level flag, benign race (both threads set same value)

### App Integration

Registered via DI as `http` singleton:

```ruby
app.post "/proxy" do |req, http:|
  result = http.post("https://api.example.com/analyze",
    json: req.body,
    headers: { "X-Api-Key" => ENV["EXTERNAL_API_KEY"] },
    timeout: 30
  )
  result.json
end
```

### Error Handling

- Timeout: raises `Whoosh::HTTP::TimeoutError` (wraps `Net::ReadTimeout`, `Net::OpenTimeout`)
- Connection refused: raises `Whoosh::HTTP::ConnectionError` (wraps `Errno::ECONNREFUSED`, `SocketError`)
- Non-2xx responses do NOT raise — check `response.ok?` or `response.status`

### Scope Exclusions

No retry logic, no circuit breaker, no request middleware.

## Files

### New Files

| File | Purpose |
|------|---------|
| `lib/whoosh/uploaded_file.rb` | UploadedFile wrapper with read/save/validate |
| `lib/whoosh/storage.rb` | Storage module with build factory |
| `lib/whoosh/storage/local.rb` | Local disk storage adapter |
| `lib/whoosh/storage/s3.rb` | S3 storage adapter (lazy aws-sdk) |
| `lib/whoosh/http.rb` | HTTP client module with get/post/put/patch/delete |
| `lib/whoosh/http/response.rb` | HTTP response wrapper |
| `spec/whoosh/uploaded_file_spec.rb` | Upload tests |
| `spec/whoosh/storage/local_spec.rb` | Local storage tests |
| `spec/whoosh/storage/s3_spec.rb` | S3 interface tests (no real S3) |
| `spec/whoosh/http_spec.rb` | HTTP client tests |
| `spec/whoosh/app_upload_spec.rb` | App integration test for file uploads |

### Modified Files

| File | Change |
|------|--------|
| `lib/whoosh.rb` | Add autoloads for UploadedFile, Storage, HTTP |
| `lib/whoosh/request.rb` | Add `#files` method |
| `lib/whoosh/app.rb` | Set `env["whoosh.storage"]` in handle_request, auto-register storage and http via DI |

## Dependencies

- No new hard dependencies
- `aws-sdk-s3` — optional, for S3 storage
- `httpx` — optional, for advanced HTTP client
