# lib/whoosh/jobs.rb
# frozen_string_literal: true

require "securerandom"

module Whoosh
  module Jobs
    autoload :MemoryBackend, "whoosh/jobs/memory_backend"
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

      def enqueue(job_class, **args)
        raise Errors::DependencyError, "Jobs not configured — boot a Whoosh::App first" unless configured?
        id = SecureRandom.uuid
        record = {
          id: id, class_name: job_class.name, args: args, status: :pending,
          result: nil, error: nil, retry_count: 0,
          created_at: Time.now.to_f, started_at: nil, completed_at: nil
        }
        @backend.save(record)
        @backend.push({ id: id, class_name: job_class.name, args: args })
        id
      end

      def find(id)
        raise Errors::DependencyError, "Jobs not configured" unless configured?
        @backend.find(id)
      end

      def reset!
        @backend = nil
        @di = nil
      end
    end
  end
end
