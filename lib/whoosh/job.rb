# frozen_string_literal: true

module Whoosh
  class Job
    class << self
      def inject(*names)
        @dependencies = names
      end

      def dependencies
        @dependencies || []
      end

      def queue(name = nil)
        if name
          @queue_name = name.to_s
        else
          @queue_name || "default"
        end
      end

      def retry_limit(n = nil)
        if n
          @retry_limit = n
        else
          @retry_limit
        end
      end

      def retry_backoff(strategy = nil)
        if strategy
          @retry_backoff = strategy
        else
          @retry_backoff || :linear
        end
      end

      def perform_async(**args)
        Jobs.enqueue(self, **args)
      end

      def perform_in(delay_seconds, **args)
        Jobs.enqueue(self, run_at: Time.now.to_f + delay_seconds, **args)
      end

      def perform_at(time, **args)
        Jobs.enqueue(self, run_at: time.to_f, **args)
      end
    end

    def perform(**args)
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end
  end
end
