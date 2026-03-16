# lib/whoosh/mcp/transport/sse.rb
# frozen_string_literal: true

module Whoosh
  module MCP
    module Transport
      class SSE
        def initialize(server)
          @server = server
        end

        def handle_request(body)
          response = begin
            request = Protocol.parse(body)
            @server.handle(request)
          rescue Protocol::ParseError => e
            Protocol.error_response(id: nil, code: -32700, message: e.message)
          end

          sse_body = response ? "data: #{Protocol.encode(response)}\n\n" : ""
          [200, { "content-type" => "text/event-stream", "cache-control" => "no-cache", "connection" => "keep-alive" }, [sse_body]]
        end
      end
    end
  end
end
