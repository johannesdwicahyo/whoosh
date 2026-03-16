# Whoosh Phase 4: Streaming Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three streaming APIs: SSE (generic events), LLM streaming (OpenAI-compatible SSE), and WebSocket (bidirectional). Uses Rack hijack for direct socket writes.

**Architecture:** `Streaming::SSE` wraps a Rack hijack socket with `event()` and `<<` methods for SSE wire format. `Streaming::LlmStream` extends SSE with OpenAI-compatible `data:` chunk format. `Streaming::WebSocket` provides bidirectional framing. All return Rack hijack responses (`[-1, {}, []]`). App exposes `stream :sse`, `stream_llm`, and `websocket` DSL methods.

**Tech Stack:** Ruby 3.4+, RSpec, rack-test. Rack hijack API for socket access.

**Spec:** `docs/superpowers/specs/2026-03-11-whoosh-design.md` (Streaming section, lines 343-414)

**Depends on:** Phase 1-3 complete (176 tests passing).

---

## Chunk 1: SSE and LLM Streaming

### Task 1: SSE Streaming

**Files:**
- Create: `lib/whoosh/streaming/sse.rb`
- Test: `spec/whoosh/streaming/sse_spec.rb`

SSE wraps an IO object (socket or StringIO for testing) with methods to write SSE-formatted events.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/streaming/sse_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Streaming::SSE do
  let(:io) { StringIO.new }
  let(:sse) { Whoosh::Streaming::SSE.new(io) }

  describe "#<<" do
    it "writes data as SSE format" do
      sse << { message: "hello" }
      io.rewind
      output = io.read
      expect(output).to include("data:")
      expect(output).to include("hello")
      expect(output).to end_with("\n\n")
    end
  end

  describe "#event" do
    it "writes a named event" do
      sse.event("status", { connected: true })
      io.rewind
      output = io.read
      expect(output).to include("event: status")
      expect(output).to include("data:")
      expect(output).to include("connected")
    end
  end

  describe "#close" do
    it "closes the stream" do
      sse.close
      io.rewind
      output = io.read
      expect(output).to include("event: close")
    end
  end

  describe "#write_raw" do
    it "writes raw string data" do
      sse << "plain text"
      io.rewind
      output = io.read
      expect(output).to include("data: plain text")
    end
  end

  describe "headers" do
    it "returns SSE content-type headers" do
      headers = Whoosh::Streaming::SSE.headers
      expect(headers["content-type"]).to eq("text/event-stream")
      expect(headers["cache-control"]).to eq("no-cache")
      expect(headers["connection"]).to eq("keep-alive")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/streaming/sse_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/streaming/sse.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module Streaming
    class SSE
      def self.headers
        {
          "content-type" => "text/event-stream",
          "cache-control" => "no-cache",
          "connection" => "keep-alive",
          "x-accel-buffering" => "no"
        }.freeze
      end

      def initialize(io)
        @io = io
        @closed = false
      end

      def <<(data)
        return if @closed

        formatted = data.is_a?(String) ? data : JSON.generate(data)
        write("data: #{formatted}\n\n")
        self
      end

      def event(name, data = nil)
        return if @closed

        write("event: #{name}\n")
        if data
          formatted = data.is_a?(String) ? data : JSON.generate(data)
          write("data: #{formatted}\n")
        end
        write("\n")
        self
      end

      def close
        return if @closed

        event("close")
        @closed = true
        @io.close if @io.respond_to?(:close) && !@io.closed?
      rescue IOError
        # Already closed
      end

      def closed?
        @closed
      end

      private

      def write(data)
        @io.write(data)
        @io.flush if @io.respond_to?(:flush)
      rescue IOError, Errno::EPIPE
        @closed = true
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/streaming/sse_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/streaming/sse.rb spec/whoosh/streaming/sse_spec.rb
git commit -m "feat: add SSE streaming with named events and auto-JSON serialization"
```

---

### Task 2: LLM Stream

**Files:**
- Create: `lib/whoosh/streaming/llm_stream.rb`
- Test: `spec/whoosh/streaming/llm_stream_spec.rb`

LlmStream extends SSE with OpenAI-compatible format: `data: {"choices":[{"delta":{"content":"..."}}]}`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/streaming/llm_stream_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Streaming::LlmStream do
  let(:io) { StringIO.new }
  let(:stream) { Whoosh::Streaming::LlmStream.new(io) }

  describe "#<<" do
    it "writes chunks in OpenAI-compatible SSE format" do
      stream << "Hello"
      io.rewind
      output = io.read
      expect(output).to include("data:")
      parsed = JSON.parse(output.match(/data: (.+)/)[1])
      expect(parsed["choices"][0]["delta"]["content"]).to eq("Hello")
    end

    it "handles object chunks with .text method" do
      chunk = double("chunk", text: "world")
      stream << chunk
      io.rewind
      output = io.read
      parsed = JSON.parse(output.match(/data: (.+)/)[1])
      expect(parsed["choices"][0]["delta"]["content"]).to eq("world")
    end
  end

  describe "#finish" do
    it "sends [DONE] marker" do
      stream.finish
      io.rewind
      output = io.read
      expect(output).to include("data: [DONE]")
    end
  end

  describe "#error" do
    it "sends error event" do
      stream.error("llm_error", "Connection failed")
      io.rewind
      output = io.read
      expect(output).to include("event: error")
      expect(output).to include("llm_error")
    end
  end

  describe "headers" do
    it "returns SSE headers" do
      headers = Whoosh::Streaming::LlmStream.headers
      expect(headers["content-type"]).to eq("text/event-stream")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/streaming/llm_stream_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/streaming/llm_stream.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module Streaming
    class LlmStream
      def self.headers
        SSE.headers
      end

      def initialize(io)
        @io = io
        @closed = false
      end

      def <<(chunk)
        return if @closed

        text = chunk.respond_to?(:text) ? chunk.text : chunk.to_s
        payload = {
          choices: [{ delta: { content: text } }]
        }
        write("data: #{JSON.generate(payload)}\n\n")
        self
      end

      def finish
        return if @closed

        write("data: [DONE]\n\n")
        @closed = true
        @io.close if @io.respond_to?(:close) && !@io.closed?
      rescue IOError
        # Already closed
      end

      def error(type, message)
        return if @closed

        write("event: error\ndata: #{JSON.generate({ error: type, message: message })}\n\n")
      end

      def closed?
        @closed
      end

      private

      def write(data)
        @io.write(data)
        @io.flush if @io.respond_to?(:flush)
      rescue IOError, Errno::EPIPE
        @closed = true
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/streaming/llm_stream_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/streaming/llm_stream.rb spec/whoosh/streaming/llm_stream_spec.rb
git commit -m "feat: add LlmStream with OpenAI-compatible SSE format and error handling"
```

---

## Chunk 2: WebSocket and App Integration

### Task 3: WebSocket

**Files:**
- Create: `lib/whoosh/streaming/websocket.rb`
- Test: `spec/whoosh/streaming/websocket_spec.rb`

Basic WebSocket wrapper for bidirectional communication.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/streaming/websocket_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Streaming::WebSocket do
  let(:io) { StringIO.new }
  let(:ws) { Whoosh::Streaming::WebSocket.new(io) }

  describe "#send" do
    it "writes text to the socket" do
      ws.send("hello")
      io.rewind
      expect(io.read).to include("hello")
    end

    it "serializes hashes to JSON" do
      ws.send({ msg: "hi" })
      io.rewind
      output = io.read
      expect(JSON.parse(output.strip)).to eq({ "msg" => "hi" })
    end
  end

  describe "#on_message" do
    it "registers a message handler" do
      received = nil
      ws.on_message { |msg| received = msg }
      ws.trigger_message("test")
      expect(received).to eq("test")
    end
  end

  describe "#on_close" do
    it "registers a close handler" do
      closed = false
      ws.on_close { closed = true }
      ws.trigger_close
      expect(closed).to be true
    end
  end

  describe "#close" do
    it "closes the connection" do
      ws.close
      expect(ws.closed?).to be true
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/streaming/websocket_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/streaming/websocket.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module Streaming
    class WebSocket
      def initialize(io)
        @io = io
        @closed = false
        @on_message = nil
        @on_close = nil
      end

      def send(data)
        return if @closed

        formatted = data.is_a?(String) ? data : JSON.generate(data)
        @io.write(formatted + "\n")
        @io.flush if @io.respond_to?(:flush)
      rescue IOError, Errno::EPIPE
        @closed = true
      end

      def on_message(&block)
        @on_message = block
      end

      def on_close(&block)
        @on_close = block
      end

      def trigger_message(msg)
        @on_message&.call(msg)
      end

      def trigger_close
        @on_close&.call
        @closed = true
      end

      def close
        @closed = true
        @io.close if @io.respond_to?(:close) && !@io.closed?
      rescue IOError
        # Already closed
      end

      def closed?
        @closed
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/streaming/websocket_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/streaming/websocket.rb spec/whoosh/streaming/websocket_spec.rb
git commit -m "feat: add WebSocket with send, message/close handlers, and JSON serialization"
```

---

### Task 4: App Streaming Integration

**Files:**
- Modify: `lib/whoosh/app.rb`
- Test: `spec/whoosh/app_streaming_spec.rb`

Add `stream` and `stream_llm` helper methods available inside endpoint blocks.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/app_streaming_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "stringio"

RSpec.describe "App streaming integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "stream :sse" do
    it "returns SSE content-type headers" do
      application.get "/events" do
        stream :sse do |out|
          out.event("status", { connected: true })
        end
      end

      get "/events"
      expect(last_response.headers["content-type"]).to eq("text/event-stream")
    end

    it "writes SSE events to response body" do
      application.get "/events" do
        stream :sse do |out|
          out.event("status", { connected: true })
          out << { data: "hello" }
        end
      end

      get "/events"
      body = last_response.body
      expect(body).to include("event: status")
      expect(body).to include("hello")
    end
  end

  describe "stream_llm" do
    it "returns SSE headers" do
      application.post "/chat" do |req|
        stream_llm do |out|
          out << "Hello"
          out << " world"
          out.finish
        end
      end

      post "/chat"
      expect(last_response.headers["content-type"]).to eq("text/event-stream")
    end

    it "writes OpenAI-compatible chunks" do
      application.post "/chat" do |req|
        stream_llm do |out|
          out << "Hello"
          out.finish
        end
      end

      post "/chat"
      body = last_response.body
      lines = body.split("\n").reject(&:empty?)
      data_line = lines.find { |l| l.start_with?("data: {") }
      parsed = JSON.parse(data_line.sub("data: ", ""))
      expect(parsed["choices"][0]["delta"]["content"]).to eq("Hello")
      expect(body).to include("data: [DONE]")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/app_streaming_spec.rb`
Expected: FAIL — `stream` method not defined

- [ ] **Step 3: Add streaming methods to App**

Read `lib/whoosh/app.rb` first. Then add these methods.

**Add to public section (after access_control method):**

```ruby
    # --- Streaming helpers (available in endpoint blocks via instance_exec) ---

    def stream(type, &block)
      io = StringIO.new
      case type
      when :sse
        sse = Streaming::SSE.new(io)
        block.call(sse)
        io.rewind
        [200, Streaming::SSE.headers, [io.read]]
      else
        raise ArgumentError, "Unknown stream type: #{type}"
      end
    end

    def stream_llm(&block)
      io = StringIO.new
      llm_stream = Streaming::LlmStream.new(io)
      block.call(llm_stream)
      io.rewind
      [200, Streaming::LlmStream.headers, [io.read]]
    end
```

**Update handle_request to handle streaming return values:**

The streaming methods return a full Rack triple `[status, headers, body]` instead of a hash. Update the inline block handler section — after calling the block, check if the result is a Rack response triple:

Replace `Response.json(result)` (the line after the handler call block) with:

```ruby
      # Return response
      if result.is_a?(Array) && result.length == 3 && result[0].is_a?(Integer)
        result # Streaming or custom Rack response
      else
        Response.json(result)
      end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/whoosh/app_streaming_spec.rb`
Expected: All pass

- [ ] **Step 5: Run full suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/whoosh/app.rb spec/whoosh/app_streaming_spec.rb
git commit -m "feat: add stream and stream_llm helpers to App with SSE response support"
```

---

### Task 5: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 2: Smoke test**

```bash
bundle exec ruby -e "
require 'whoosh'
require 'rack/test'
include Rack::Test::Methods

app_instance = Whoosh::App.new

app_instance.get '/events' do
  stream :sse do |out|
    out.event('greeting', { msg: 'hello' })
    out << { data: 'world' }
  end
end

app_instance.post '/chat' do |req|
  stream_llm do |out|
    %w[Hello\  World !].each { |chunk| out << chunk }
    out.finish
  end
end

define_method(:app) { app_instance.to_rack }

get '/events'
puts \"SSE status: #{last_response.status}\"
puts \"SSE content-type: #{last_response.content_type}\"
puts \"SSE body:\"
puts last_response.body

post '/chat'
puts \"LLM status: #{last_response.status}\"
puts \"LLM body:\"
puts last_response.body

puts 'Phase 4 Streaming working!'
" 2>/dev/null
```

---

## Phase 4 Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] SSE streaming with named events and data
- [ ] LLM streaming with OpenAI-compatible format
- [ ] WebSocket with send, message/close handlers
- [ ] App `stream :sse` and `stream_llm` helpers
- [ ] Streaming returns proper SSE headers
- [ ] Rack response passthrough for streaming
- [ ] All Phase 1-3 tests still pass

## Next Phase

After Phase 4 passes, proceed to **Phase 5: MCP** — adding Model Context Protocol server and client.
