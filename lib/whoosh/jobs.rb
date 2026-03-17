# frozen_string_literal: true

require "securerandom"

module Whoosh
  module Jobs
    autoload :MemoryBackend, "whoosh/jobs/memory_backend"
    autoload :RedisBackend,  "whoosh/jobs/redis_backend"
    autoload :Worker,        "whoosh/jobs/worker"

    @backend = nil
    @di = nil

    class << self
      attr_reader :backend, :di

      def configure(backend:, di: nil)
        @backend = backend
        @di = di
      end

      def configured?
        !!@backend
      end

      def enqueue(job_class, run_at: nil, **args)
        raise Errors::DependencyError, "Jobs not configured — boot a Whoosh::App first" unless configured?

        id = SecureRandom.uuid
        queue_name = job_class.respond_to?(:queue) ? job_class.queue : "default"
        record = {
          id: id,
          class_name: job_class.name,
          args: args,
          queue: queue_name,
          status: run_at ? :scheduled : :pending,
          run_at: run_at,
          result: nil,
          error: nil,
          retry_count: 0,
          created_at: Time.now.to_f,
          started_at: nil,
          completed_at: nil
        }
        @backend.save(record)
        @backend.push({ id: id, class_name: job_class.name, args: args, queue: queue_name, run_at: run_at })
        id
      end

      def find(id)
        raise Errors::DependencyError, "Jobs not configured" unless configured?
        @backend.find(id)
      end

      # Build the right backend from config (auto-detect pattern)
      def build_backend(config_data = {})
        jobs_config = config_data["jobs"] || {}
        redis_url = ENV["REDIS_URL"] || jobs_config["redis_url"]

        if redis_url && jobs_config["backend"] != "memory"
          RedisBackend.new(url: redis_url)
        else
          MemoryBackend.new
        end
      end

      def reset!
        @backend = nil
        @di = nil
      end
    end
  end
end
