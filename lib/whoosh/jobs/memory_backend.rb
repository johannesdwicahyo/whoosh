# lib/whoosh/jobs/memory_backend.rb
# frozen_string_literal: true

module Whoosh
  module Jobs
    class MemoryBackend
      def initialize
        @queue = []
        @records = {}
        @mutex = Mutex.new
        @cv = ConditionVariable.new
      end

      def push(job_data)
        @mutex.synchronize do
          @queue << job_data
          @cv.signal
        end
      end

      def pop(timeout: 5)
        @mutex.synchronize do
          @cv.wait(@mutex, timeout) if @queue.empty?
          @queue.shift
        end
      end

      def save(record)
        @mutex.synchronize { @records[record[:id]] = record }
      end

      def find(id)
        @mutex.synchronize { @records[id]&.dup }
      end

      def size
        @mutex.synchronize { @queue.size }
      end

      def shutdown
        @mutex.synchronize { @cv.broadcast }
      end
    end
  end
end
