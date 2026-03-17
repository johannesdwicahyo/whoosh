# frozen_string_literal: true

require "securerandom"

module Whoosh
  module Middleware
    class RequestLogger
      def initialize(app, logger:, metrics: nil)
        @app = app
        @logger = logger
        @metrics = metrics
      end

      def call(env)
        request_id = env["HTTP_X_REQUEST_ID"] || SecureRandom.uuid
        env["whoosh.request_id"] = request_id

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status, headers, body = @app.call(env)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        headers = headers.dup
        headers["x-request-id"] = request_id

        @logger.info("request_complete",
          method: env["REQUEST_METHOD"], path: env["PATH_INFO"],
          status: status, duration_ms: duration_ms, request_id: request_id
        )

        if @metrics
          @metrics.increment("whoosh_requests_total", labels: { method: env["REQUEST_METHOD"], path: env["PATH_INFO"], status: status.to_s })
          @metrics.observe("whoosh_request_duration_seconds", duration_ms / 1000.0, labels: { path: env["PATH_INFO"] })
        end

        [status, headers, body]
      end
    end
  end
end
