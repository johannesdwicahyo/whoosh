# frozen_string_literal: true

require "json"

module Whoosh
  class Logger
    LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze

    def initialize(output: $stdout, format: :json, level: :info)
      @output = output
      @format = format
      @level = LEVELS[level.to_sym] || 1
    end

    def debug(event, **data)
      log(:debug, event, **data)
    end

    def info(event, **data)
      log(:info, event, **data)
    end

    def warn(event, **data)
      log(:warn, event, **data)
    end

    def error(event, **data)
      log(:error, event, **data)
    end

    def with_context(**context)
      ScopedLogger.new(self, **context)
    end

    class ScopedLogger
      def initialize(logger, **context)
        @logger = logger
        @context = context
      end

      def debug(event, **data) = @logger.debug(event, **@context, **data)
      def info(event, **data) = @logger.info(event, **@context, **data)
      def warn(event, **data) = @logger.warn(event, **@context, **data)
      def error(event, **data) = @logger.error(event, **@context, **data)
    end

    private

    def log(level, event, **data)
      return if LEVELS[level] < @level

      entry = { ts: Time.now.utc.iso8601, level: level.to_s, event: event }.merge(data)

      case @format
      when :json
        @output.puts(JSON.generate(entry))
      when :text
        @output.puts("[#{entry[:ts]}] #{level.to_s.upcase} #{event} #{data.map { |k, v| "#{k}=#{v}" }.join(' ')}")
      end
    end
  end
end
