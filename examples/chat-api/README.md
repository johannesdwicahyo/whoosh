# Chat API Example

A reference implementation demonstrating all major Whoosh framework features.

## Features Demonstrated

- Class-based endpoints with schema validation
- OpenAPI metadata and documentation
- API key authentication
- Rate limiting per route
- Role-based access control
- Inline streaming (chunked transfer)
- Server-Sent Events (SSE)
- Health check endpoint
- MCP-compatible endpoint tagging

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

| Method | Path          | Auth     | Description                          |
|--------|---------------|----------|--------------------------------------|
| GET    | /health       | none     | Health check returning version info  |
| POST   | /chat         | api_key  | Chat with echo model (MCP-tagged)    |
| POST   | /users        | api_key  | Create a new user                    |
| POST   | /chat/stream  | api_key  | Streaming chat response              |
| GET    | /events       | none     | SSE stream of server events          |
| GET    | /openapi.json | none     | OpenAPI 3.0 schema                   |

## Example Requests

```bash
# Health check
curl http://localhost:9292/health

# Chat (requires API key)
curl -X POST http://localhost:9292/chat \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-demo-key" \
  -d '{"message": "Hello!", "model": "default"}'

# Create user
curl -X POST http://localhost:9292/users \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-demo-key" \
  -d '{"name": "Alice", "email": "alice@example.com"}'

# Streaming chat
curl -N -X POST http://localhost:9292/chat/stream \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-demo-key" \
  -d '{"message": "Tell me a story"}'

# SSE events
curl -N http://localhost:9292/events
```
