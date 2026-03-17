# lib/whoosh/streaming/stream_body.rb
# frozen_string_literal: true

require "thread"

module Whoosh
  module Streaming
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

    class StreamBody
      def initialize(queue_size: 64, &producer)
        @queue = SizedQueue.new(queue_size)
        @producer = producer
        @thread = nil
      end

      def each
        @thread = Thread.new do
          out = QueueWriter.new(@queue)
          @producer.call(out)
        rescue => e
          # Producer failed — just end the stream
        ensure
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
  end
end
