# lib/whoosh/http.rb
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Whoosh
  module HTTP
    autoload :Response, "whoosh/http/response"

    class TimeoutError < Errors::WhooshError; end
    class ConnectionError < Errors::WhooshError; end

    class << self
      def get(url, headers: {}, timeout: 30)
        request(:get, url, headers: headers, timeout: timeout)
      end

      def post(url, json: nil, body: nil, headers: {}, timeout: 30)
        request(:post, url, json: json, body: body, headers: headers, timeout: timeout)
      end

      def put(url, json: nil, body: nil, headers: {}, timeout: 30)
        request(:put, url, json: json, body: body, headers: headers, timeout: timeout)
      end

      def patch(url, json: nil, body: nil, headers: {}, timeout: 30)
        request(:patch, url, json: json, body: body, headers: headers, timeout: timeout)
      end

      def delete(url, headers: {}, timeout: 30)
        request(:delete, url, headers: headers, timeout: timeout)
      end

      # Run multiple HTTP requests concurrently
      def concurrent(*requests)
        threads = requests.map do |req|
          method = req[:method] || :get
          url = req[:url]
          opts = req.except(:method, :url)
          Thread.new { send(method, url, **opts) }
        end
        threads.map(&:value)
      end

      # Returns an async client for non-blocking requests
      def async
        AsyncClient.new
      end

      private

      def request(method, url, json: nil, body: nil, headers: {}, timeout: 30)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = timeout
        http.read_timeout = timeout

        request_body = json ? JSON.generate(json) : body
        headers = { "Content-Type" => "application/json" }.merge(headers) if json

        req = build_net_request(method, uri, headers)
        req.body = request_body if request_body

        response = http.request(req)
        Response.new(status: response.code.to_i, body: response.body || "", headers: response.each_header.to_h)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise TimeoutError, e.message
      rescue Errno::ECONNREFUSED, SocketError, Errno::EHOSTUNREACH => e
        raise ConnectionError, e.message
      end

      def build_net_request(method, uri, headers)
        path = uri.request_uri
        req = case method
        when :get then Net::HTTP::Get.new(path)
        when :post then Net::HTTP::Post.new(path)
        when :put then Net::HTTP::Put.new(path)
        when :patch then Net::HTTP::Patch.new(path)
        when :delete then Net::HTTP::Delete.new(path)
        end
        headers.each { |k, v| req[k] = v }
        req
      end
    end

    class AsyncClient
      def get(url, **opts) = Thread.new { HTTP.get(url, **opts) }
      def post(url, **opts) = Thread.new { HTTP.post(url, **opts) }
      def put(url, **opts) = Thread.new { HTTP.put(url, **opts) }
      def patch(url, **opts) = Thread.new { HTTP.patch(url, **opts) }
      def delete(url, **opts) = Thread.new { HTTP.delete(url, **opts) }
    end
  end
end
