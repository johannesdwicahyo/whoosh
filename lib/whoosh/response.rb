# frozen_string_literal: true

module Whoosh
  class Response
    JSON_HEADERS = { "content-type" => "application/json" }.freeze

    def self.json(data, status: 200, headers: {})
      body = Serialization::Json.encode(data)
      response_headers = if headers.empty?
        { "content-type" => "application/json", "content-length" => body.bytesize.to_s }
      else
        { "content-type" => "application/json", "content-length" => body.bytesize.to_s }.merge(headers)
      end
      [status, response_headers, [body]]
    end

    def self.error(error, production: false)
      headers = { "content-type" => "application/json" }

      if error.is_a?(Errors::RateLimitExceeded)
        headers["retry-after"] = error.retry_after.to_s
      end

      body = if error.is_a?(Errors::HttpError)
        error.to_h
      else
        hash = { error: "internal_error" }
        hash[:message] = error.message unless production
        hash
      end

      [error.is_a?(Errors::HttpError) ? error.status : 500, headers, [Serialization::Json.encode(body)]]
    end

    def self.not_found
      error(Errors::NotFoundError.new)
    end
  end
end
