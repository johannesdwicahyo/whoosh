# frozen_string_literal: true

module Whoosh
  module Jobs
    class Worker
      def initialize(backend:, di: nil, max_retries: 3, retry_delay: 5, instrumentation: nil, logger: nil)
        @backend = backend
        @di = di
        @max_retries = max_retries
        @retry_delay = retry_delay
        @instrumentation = instrumentation
        @logger = logger
        @running = true
      end

      def run_once(timeout: 5)
        job_data = @backend.pop(timeout: timeout)
        return unless job_data
        execute(job_data)
      end

      def run_loop
        while @running
          run_once
        end
      end

      def stop
        @running = false
      end

      private

      def execute(job_data)
        id = job_data[:id]
        class_name = job_data[:class_name]

        # Skip scheduled jobs that aren't ready yet
        if job_data[:run_at] && job_data[:run_at].to_f > Time.now.to_f
          @backend.push(job_data)
          return
        end

        record = @backend.find(id) || {}
        record = record.merge(id: id, status: :running, started_at: Time.now.to_f)
        @backend.save(record)

        @logger&.info("job_started", job_id: id, class: class_name)

        job_class = Object.const_get(class_name)
        job = job_class.new

        # Determine retry settings from job class or defaults
        max_retries = job_class.respond_to?(:retry_limit) && job_class.retry_limit ? job_class.retry_limit : @max_retries
        backoff_strategy = job_class.respond_to?(:retry_backoff) ? job_class.retry_backoff : :linear

        # Inject DI deps
        if @di && job_class.respond_to?(:dependencies)
          job_class.dependencies.each do |dep|
            value = @di.resolve(dep)
            job.instance_variable_set(:"@#{dep}", value)
            job.define_singleton_method(dep) { instance_variable_get(:"@#{dep}") }
          end
        end

        args = job_data[:args]
        args = args.transform_keys(&:to_sym) if args.is_a?(Hash)
        result = job.perform(**args)
        serialized = Serialization::Json.decode(Serialization::Json.encode(result))

        @backend.save(record.merge(status: :completed, result: serialized, completed_at: Time.now.to_f))
        @logger&.info("job_completed", job_id: id, class: class_name)

      rescue => e
        record = @backend.find(id) || { id: id }
        retry_count = (record[:retry_count] || 0) + 1

        if retry_count <= max_retries
          # Non-blocking retry: re-enqueue with delay timestamp instead of sleeping
          delay = calculate_delay(retry_count, backoff_strategy)
          run_at = Time.now.to_f + delay
          @backend.save(record.merge(retry_count: retry_count, status: :scheduled, run_at: run_at))
          @backend.push(job_data.merge(run_at: run_at))
          @logger&.warn("job_retry", job_id: id, class: class_name, retry_count: retry_count, delay: delay)
        else
          error = { message: e.message, backtrace: e.backtrace&.first(10)&.join("\n") }
          @backend.save(record.merge(
            status: :failed, error: error, retry_count: retry_count, completed_at: Time.now.to_f
          ))
          @instrumentation&.emit(:job_failed, { job_id: id, error: error })
          @logger&.error("job_failed", job_id: id, class: class_name, error: e.message)
        end
      end

      def calculate_delay(retry_count, strategy)
        case strategy
        when :exponential
          @retry_delay * (2**(retry_count - 1))  # 5, 10, 20, 40...
        when :linear
          @retry_delay * retry_count              # 5, 10, 15, 20...
        else
          @retry_delay
        end
      end
    end
  end
end
