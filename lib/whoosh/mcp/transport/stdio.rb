# lib/whoosh/mcp/transport/stdio.rb
# frozen_string_literal: true

module Whoosh
  module MCP
    module Transport
      class Stdio
        def initialize(server, input: $stdin, output: $stdout)
          @server = server
          @input = input
          @output = output
        end

        def run
          @output.sync = true
          @input.each_line do |line|
            next if line.strip.empty?
            begin
              request = Protocol.parse(line)
              response = @server.handle(request)
              if response
                @output.puts(Protocol.encode(response))
              end
            rescue Protocol::ParseError => e
              error = Protocol.error_response(id: nil, code: -32700, message: e.message)
              @output.puts(Protocol.encode(error))
            end
          end
        end
      end
    end
  end
end
