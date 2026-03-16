# Chat API Example

A reference implementation demonstrating all major Whoosh framework features.

## Features Demonstrated

- Class-based endpoints with schema validation
- OpenAPI 3.1 auto-generation + Swagger UI + ReDoc
- API key authentication with rate limiting tiers
- Role-based model access control
- Token usage tracking with billing hook
- Error tracking via instrumentation
- LLM streaming (OpenAI-compatible SSE)
- Server-Sent Events (SSE)
- Health check with probes
- MCP tool auto-registration (per-route and per-group)
- Performance optimization (Oj + YJIT auto-enabled)
- Whoosh::Test DSL for testing

## Setup

```bash
bundle install
```

## Run

```bash
bundle exec rackup config.ru
# Server starts at http://localhost:9292
```

## Endpoints

| Method | Path             | Auth    | Description                          |
|--------|------------------|---------|--------------------------------------|
| GET    | /health          | none    | Health check with probes             |
| POST   | /chat            | none    | Chat endpoint (MCP tool)             |
| POST   | /users           | none    | Create user with schema validation   |
| POST   | /chat/stream     | api_key | Streaming chat (SSE)                 |
| GET    | /events          | none    | SSE server events                    |
| POST   | /tools/translate | none    | Translation (MCP group tool)         |
| GET    | /healthz         | none    | Built-in health check                |
| GET    | /openapi.json    | none    | OpenAPI 3.1 spec                     |
| GET    | /docs            | none    | Swagger UI                           |
| GET    | /redoc           | none    | ReDoc                                |

## Example Requests

```bash
# Health check
curl http://localhost:9292/health

# Chat (MCP-tagged)
curl -X POST http://localhost:9292/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello!", "model": "default"}'

# Streaming chat (requires API key)
curl -N -X POST http://localhost:9292/chat/stream \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-demo-key" \
  -d '{"message": "Tell me a story"}'

# SSE events
curl -N http://localhost:9292/events

# MCP tools list
curl http://localhost:9292/openapi.json | jq '.paths | keys'

# ReDoc docs
open http://localhost:9292/redoc
```

## Testing

```ruby
require "whoosh/test"

class ChatTest
  include Whoosh::Test

  def app = APP.to_rack

  def test_chat
    post_json "/chat", { message: "hi" }
    assert_response 200
    assert_json(reply: "Echo: hi")
  end
end
```
