# frozen_string_literal: true

require "json"
require "digest"
require "base64"

module Whoosh
  module Streaming
    class WebSocket
      GUID = "258EAFA5-E914-47DA-95CA-5AB5DC65C3E5"

      attr_reader :env

      def initialize(env)
        @env = env
        @io = nil
        @closed = false
        @on_message = nil
        @on_close = nil
        @on_open = nil
      end

      # Check if the request is a WebSocket upgrade
      def self.websocket?(env)
        env["HTTP_UPGRADE"]&.downcase == "websocket" &&
          env["HTTP_CONNECTION"]&.downcase&.include?("upgrade")
      end

      # Register callbacks
      def on_open(&block)
        @on_open = block
      end

      def on_message(&block)
        @on_message = block
      end

      def on_close(&block)
        @on_close = block
      end

      # Send data to the client
      def send(data)
        return if @closed
        formatted = data.is_a?(String) ? data : JSON.generate(data)
        write_frame(formatted)
      end

      def close
        return if @closed
        @closed = true
        write_close_frame
        @io&.close rescue nil
        @on_close&.call
      end

      def closed?
        @closed
      end

      # Returns a Rack response that hijacks the connection
      def rack_response
        unless self.class.websocket?(@env)
          return [400, { "content-type" => "text/plain" }, ["Not a WebSocket request"]]
        end

        # WebSocket handshake
        key = @env["HTTP_SEC_WEBSOCKET_KEY"]
        accept = Base64.strict_encode64(Digest::SHA1.digest(key + GUID))

        headers = {
          "Upgrade" => "websocket",
          "Connection" => "Upgrade",
          "Sec-WebSocket-Accept" => accept
        }

        # Use rack.hijack to take over the connection
        if @env["rack.hijack"]
          @env["rack.hijack"].call
          @io = @env["rack.hijack_io"]

          # Send handshake response manually
          @io.write("HTTP/1.1 101 Switching Protocols\r\n")
          headers.each { |k, v| @io.write("#{k}: #{v}\r\n") }
          @io.write("\r\n")
          @io.flush

          # Notify open
          @on_open&.call

          # Start reading frames in a thread
          Thread.new { read_loop }

          # Return a dummy response (connection is hijacked)
          [-1, {}, []]
        else
          # Fallback: return 101 and let the server handle hijack
          [101, headers, []]
        end
      end

      # For testing — simulate without real socket
      def trigger_message(msg)
        @on_message&.call(msg)
      end

      def trigger_close
        @on_close&.call
        @closed = true
      end

      private

      def read_loop
        while !@closed && @io && !@io.closed?
          frame = read_frame
          break unless frame

          case frame[:opcode]
          when 0x1 # Text frame
            @on_message&.call(frame[:data])
          when 0x8 # Close frame
            close
            break
          when 0x9 # Ping
            write_pong(frame[:data])
          end
        end
      rescue IOError, Errno::ECONNRESET, Errno::EPIPE
        @closed = true
        @on_close&.call
      end

      def read_frame
        return nil unless @io && !@io.closed?

        first_byte = @io.readbyte
        fin = (first_byte & 0x80) != 0
        opcode = first_byte & 0x0F

        second_byte = @io.readbyte
        masked = (second_byte & 0x80) != 0
        length = second_byte & 0x7F

        if length == 126
          length = @io.read(2).unpack1("n")
        elsif length == 127
          length = @io.read(8).unpack1("Q>")
        end

        mask_key = masked ? @io.read(4).bytes : nil
        payload = @io.read(length)&.bytes || []

        if masked && mask_key
          payload = payload.each_with_index.map { |b, i| b ^ mask_key[i % 4] }
        end

        { opcode: opcode, data: payload.pack("C*"), fin: fin }
      rescue EOFError, IOError
        nil
      end

      def write_frame(data, opcode: 0x1)
        return unless @io && !@io.closed?

        bytes = data.encode("UTF-8").bytes
        frame = [0x80 | opcode] # FIN + opcode

        if bytes.length < 126
          frame << bytes.length
        elsif bytes.length < 65536
          frame << 126
          frame += [bytes.length].pack("n").bytes
        else
          frame << 127
          frame += [bytes.length].pack("Q>").bytes
        end

        frame += bytes
        @io.write(frame.pack("C*"))
        @io.flush
      rescue IOError, Errno::EPIPE
        @closed = true
      end

      def write_close_frame
        write_frame("", opcode: 0x8) rescue nil
      end

      def write_pong(data)
        write_frame(data, opcode: 0xA) rescue nil
      end
    end
  end
end
