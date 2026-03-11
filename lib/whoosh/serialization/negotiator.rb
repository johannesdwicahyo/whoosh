# frozen_string_literal: true

module Whoosh
  module Serialization
    class Negotiator
      SERIALIZERS = {
        "application/json" => -> { Json }
      }.freeze

      def self.for_accept(accept_header)
        return Json if accept_header.nil? || accept_header.empty?

        accept_header.split(",").each do |media_type|
          type = media_type.strip.split(";").first.strip
          return Json if type == "*/*"

          serializer = SERIALIZERS[type]
          return serializer.call if serializer
        end

        Json # fallback
      end

      def self.for_content_type(content_type)
        return Json if content_type.nil? || content_type.empty?

        type = content_type.split(";").first.strip
        serializer = SERIALIZERS[type]
        serializer ? serializer.call : Json
      end
    end
  end
end
