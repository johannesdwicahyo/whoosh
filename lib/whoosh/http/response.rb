# lib/whoosh/http/response.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module HTTP
    class Response
      attr_reader :status, :body, :headers

      def initialize(status:, body:, headers: {})
        @status = status
        @body = body
        @headers = headers
      end

      def json
        @json ||= JSON.parse(@body)
      end

      def ok?
        @status >= 200 && @status < 300
      end
    end
  end
end
