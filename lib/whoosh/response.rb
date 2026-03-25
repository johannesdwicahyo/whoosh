# frozen_string_literal: true

module Whoosh
  class Response
    JSON_HEADERS = { "content-type" => "application/json" }.freeze

    MIME_TYPES = { ".html" => "text/html", ".json" => "application/json", ".css" => "text/css",
      ".js" => "application/javascript", ".png" => "image/png", ".jpg" => "image/jpeg",
      ".svg" => "image/svg+xml", ".pdf" => "application/pdf", ".txt" => "text/plain" }.freeze

    def self.redirect(url, status: 302)
      [status, { "location" => url }, []]
    end

    def self.download(data, filename:, content_type: "application/octet-stream")
      [200, { "content-type" => content_type, "content-disposition" => "attachment; filename=\"#{filename}\"" }, [data]]
    end

    def self.file(path, content_type: nil)
      raise Errors::NotFoundError unless File.exist?(path)
      ct = content_type || guess_content_type(path)
      body = File.binread(path)
      [200, { "content-type" => ct, "content-length" => body.bytesize.to_s }, [body]]
    end

    def self.guess_content_type(path)
      ext = File.extname(path).downcase
      MIME_TYPES[ext] || "application/octet-stream"
    end

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
