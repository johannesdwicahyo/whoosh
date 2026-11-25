module Whoosh
  module Stores
    # In-process store for rate limits and idempotency keys. Fine for one
    # process; use Stores::Cache with a shared cache when you run several.
    class Memory
      def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @data = {}
        @mutex = Mutex.new
        @clock = clock
        @writes = 0
      end

      def increment(key, ttl:)
        @mutex.synchronize do
          prune
          entry = live(key)
          count = (entry ? entry[0] : 0) + 1
          @data[key] = [count, entry ? entry[1] : now + ttl]
          count
        end
      end

      def read(key)
        @mutex.synchronize { live(key)&.first }
      end

      def write(key, value, ttl:)
        @mutex.synchronize do
          prune
          @data[key] = [value, now + ttl]
        end
        true
      end

      # Atomic "set if absent". Returns true when this call wrote the value.
      def write_unless_exists(key, value, ttl:)
        @mutex.synchronize do
          return false if live(key)

          @data[key] = [value, now + ttl]
          true
        end
      end

      def delete(key)
        @mutex.synchronize { @data.delete(key) }
        true
      end

      def clear
        @mutex.synchronize { @data.clear }
      end

      private

      def now = @clock.call

      def live(key)
        entry = @data[key]
        return nil unless entry
        return entry if entry[1] > now

        @data.delete(key)
        nil
      end

      def prune
        @writes += 1
        return unless (@writes % 1000).zero?

        t = now
        @data.delete_if { |_, (_, expires)| expires <= t }
      end
    end
  end
end
