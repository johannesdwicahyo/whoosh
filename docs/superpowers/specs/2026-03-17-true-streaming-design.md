# Whoosh True Streaming Design

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Replace buffered StringIO streaming with true chunked streaming via SizedQueue

## Overview

Current streaming (`stream_llm`, `stream :sse`) writes all chunks to a `StringIO` buffer then returns the entire body at once. This defeats the purpose of streaming — clients don't see tokens until the entire LLM response is complete.

Fix: introduce `StreamBody` — a Rack body that bridges a producer thread (writing chunks) and the server's response consumer (reading via `each`) through a `SizedQueue`.

## StreamBody

```ruby
# Implements Rack's streaming body interface
class Whoosh::Streaming::StreamBody
  def initialize(queue_size: 64, &producer)
    @queue = SizedQueue.new(queue_size)
    @producer = producer
    @thread = nil
  end

  # Rack calls this to read the response
  def each
    @thread = Thread.new do
      out = QueueWriter.new(@queue)
      @producer.call(out)
      @queue.push(:done)
    rescue => e
      @queue.push(:done)
    end

    while (chunk = @queue.pop) != :done
      yield chunk
    end
  end

  def close
    @thread&.kill
  end
end
```

`QueueWriter` is a thin adapter that SSE and LlmStream write to instead of an IO object:

```ruby
class QueueWriter
  def initialize(queue)
    @queue = queue
    @closed = false
  end

  def write(data)
    return if @closed
    @queue.push(data)
  end

  def flush
    # no-op — queue delivers immediately
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end
end
```

## Updated App Helpers

```ruby
# stream :sse — true streaming
def stream(type, &block)
  case type
  when :sse
    body = Streaming::StreamBody.new do |out|
      sse = Streaming::SSE.new(out)
      block.call(sse)
    end
    [200, Streaming::SSE.headers, body]
  end
end

# stream_llm — true streaming
def stream_llm(&block)
  body = Streaming::StreamBody.new do |out|
    llm_stream = Streaming::LlmStream.new(out)
    block.call(llm_stream)
    llm_stream.finish
  end
  [200, Streaming::LlmStream.headers, body]
end
```

## How It Works

1. Endpoint handler calls `stream_llm { |out| ... }`
2. App returns `[200, headers, StreamBody]` immediately — headers sent to client
3. Server calls `body.each { |chunk| socket.write(chunk) }`
4. `each` starts producer thread, blocks on `@queue.pop`
5. Producer writes SSE-formatted chunks to `QueueWriter`
6. `QueueWriter#write` pushes to `SizedQueue`
7. `each` yields chunk to server → server writes to socket → client sees token
8. When producer finishes, pushes `:done` sentinel → `each` loop exits
9. If client disconnects, server calls `body.close` → producer thread killed

## Backpressure

`SizedQueue` capacity defaults to 64 chunks. If client reads slowly:
- Queue fills up
- `QueueWriter#write` (called by producer) blocks on `@queue.push`
- Producer pauses until consumer catches up
- No unbounded memory growth

## Backward Compatibility

- `Streaming::SSE` and `Streaming::LlmStream` already write to any IO-like object (anything with `write` and `flush`)
- `QueueWriter` implements `write`, `flush`, `close`, `closed?` — drop-in replacement for `StringIO`
- Existing tests that use `StringIO` directly still work (unit tests for SSE/LlmStream)
- App integration tests need updating: `last_response.body` in rack-test collects all chunks, so test assertions stay the same

## Files

### New Files

| File | Purpose |
|------|---------|
| `lib/whoosh/streaming/stream_body.rb` | StreamBody (Rack body) + QueueWriter |
| `spec/whoosh/streaming/stream_body_spec.rb` | StreamBody unit tests |

### Modified Files

| File | Change |
|------|--------|
| `lib/whoosh/app.rb` | Update `stream` and `stream_llm` to use StreamBody |
| `lib/whoosh.rb` | Add autoload for StreamBody if needed |

## Dependencies

None — uses Ruby stdlib `SizedQueue` (part of `thread` library, always available).
