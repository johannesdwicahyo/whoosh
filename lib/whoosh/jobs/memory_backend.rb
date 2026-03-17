# frozen_string_literal: true

module Whoosh
  module Jobs
    class MemoryBackend
      def initialize
        @queue = []
        @scheduled = []
        @records = {}
        @mutex = Mutex.new
        @cv = ConditionVariable.new
      end

      def push(job_data)
        @mutex.synchronize do
          if job_data[:run_at] && job_data[:run_at] > Time.now.to_f
            @scheduled << job_data
            @scheduled.sort_by! { |j| j[:run_at] }
          else
            @queue << job_data
          end
          @cv.signal
        end
      end

      def pop(timeout: 5)
        @mutex.synchronize do
          # Promote scheduled jobs that are ready
          promote_scheduled

          if @queue.empty?
            @cv.wait(@mutex, timeout)
            promote_scheduled
          end
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
        @mutex.synchronize { @queue.size + @scheduled.size }
      end

      def pending_count
        @mutex.synchronize { @queue.size }
      end

      def scheduled_count
        @mutex.synchronize { @scheduled.size }
      end

      def shutdown
        @mutex.synchronize { @cv.broadcast }
      end

      private

      def promote_scheduled
        now = Time.now.to_f
        ready = []
        remaining = []
        @scheduled.each do |job|
          if job[:run_at] <= now
            ready << job
          else
            remaining << job
          end
        end
        @scheduled = remaining
        @queue.concat(ready)
      end
    end
  end
end
