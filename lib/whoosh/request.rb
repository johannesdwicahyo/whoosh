# frozen_string_literal: true

require "json"
require "securerandom"
require "rack"

module Whoosh
  class Request
    attr_accessor :path_params
    attr_reader :env

    def initialize(env)
      @env = env
      @rack_request = Rack::Request.new(env)
      @path_params = {}
    end

    def method
      @rack_request.request_method
    end

    def path
      @rack_request.path_info
    end

    def params
      @params ||= query_params.merge(@path_params)
    end

    def query_params
      @query_params ||= Rack::Utils.parse_query(@rack_request.query_string)
    end

    def body
      @body ||= parse_body
    end

    def headers
      @headers ||= extract_headers
    end

    def id
      @id ||= @env["whoosh.request_id"] || headers["X-Request-Id"] || SecureRandom.uuid
    end

    def content_type
      @rack_request.content_type
    end

    def logger
      @logger ||= begin
        base_logger = @env["whoosh.logger"]
        base_logger&.with_context(request_id: id)
      end
    end

    def files
      @files ||= begin
        storage = @env["whoosh.storage"]
        form_data = @rack_request.params
        form_data.each_with_object({}) do |(key, value), hash|
          next unless value.is_a?(Hash) && value[:tempfile]
          hash[key] = UploadedFile.new(value, storage: storage)
        end
      end
    end

    private

    def parse_body
      raw = @rack_request.body&.read
      return nil if raw.nil? || raw.empty?

      @rack_request.body.rewind if @rack_request.body.respond_to?(:rewind)

      case content_type
      when /json/
        JSON.parse(raw)
      else
        raw
      end
    end

    def extract_headers
      @env.each_with_object({}) do |(key, value), headers|
        next unless key.start_with?("HTTP_")

        header_name = key.sub("HTTP_", "").split("_").map(&:capitalize).join("-")
        headers[header_name] = value
      end
    end
  end
end
