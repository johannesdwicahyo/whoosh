# lib/whoosh/jobs/worker.rb
# frozen_string_literal: true

module Whoosh
  module Jobs
    class Worker
      def initialize(backend:, di: nil, max_retries: 3, retry_delay: 5, instrumentation: nil)
        @backend = backend
        @di = di
        @max_retries = max_retries
        @retry_delay = retry_delay
        @instrumentation = instrumentation
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
        record = @backend.find(id) || {}
        record = record.merge(status: :running, started_at: Time.now.to_f)
        @backend.save(record)

        job_class = Object.const_get(job_data[:class_name])
        job = job_class.new

        # Inject DI deps
        if @di && job_class.respond_to?(:dependencies)
          job_class.dependencies.each do |dep|
            value = @di.resolve(dep)
            job.instance_variable_set(:"@#{dep}", value)
            job.define_singleton_method(dep) { instance_variable_get(:"@#{dep}") }
          end
        end

        args = job_data[:args].transform_keys(&:to_sym)
        result = job.perform(**args)
        serialized = Serialization::Json.decode(Serialization::Json.encode(result))

        @backend.save(record.merge(status: :completed, result: serialized, completed_at: Time.now.to_f))
      rescue => e
        record = @backend.find(id) || {}
        retry_count = (record[:retry_count] || 0) + 1

        if retry_count <= @max_retries
          sleep(@retry_delay) if @retry_delay > 0
          @backend.save(record.merge(retry_count: retry_count, status: :pending))
          @backend.push(job_data)
        else
          error = { message: e.message, backtrace: e.backtrace&.first(10)&.join("\n") }
          @backend.save(record.merge(status: :failed, error: error, retry_count: retry_count, completed_at: Time.now.to_f))
          @instrumentation&.emit(:job_failed, { job_id: id, error: error })
        end
      end
    end
  end
end
