# frozen_string_literal: true

module Whoosh
  module Middleware
    class RequestLogger
      def initialize(app, logger:)
        @app = app
        @logger = logger
      end

      def call(env)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        status, headers, body = @app.call(env)

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        @logger.info("request_complete",
          method: env["REQUEST_METHOD"],
          path: env["PATH_INFO"],
          status: status,
          duration_ms: duration_ms,
          request_id: env["HTTP_X_REQUEST_ID"]
        )

        [status, headers, body]
      end
    end
  end
end
