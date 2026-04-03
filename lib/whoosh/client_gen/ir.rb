# frozen_string_literal: true

module Whoosh
  module ClientGen
    module IR
      Endpoint = Struct.new(:method, :path, :action, :request_schema, :response_schema, :pagination, keyword_init: true) do
        def initialize(method:, path:, action:, request_schema: nil, response_schema: nil, pagination: false)
          super
        end
      end

      Schema = Struct.new(:name, :fields, keyword_init: true)

      Resource = Struct.new(:name, :endpoints, :fields, keyword_init: true) do
        def crud_actions
          endpoints.map(&:action)
        end
      end

      Auth = Struct.new(:type, :endpoints, :oauth_providers, keyword_init: true) do
        def initialize(type:, endpoints:, oauth_providers: [])
          super
        end
      end

      AppSpec = Struct.new(:auth, :resources, :streaming, :base_url, keyword_init: true) do
        def has_resources?
          resources && !resources.empty?
        end

        def has_auth?
          !auth.nil?
        end
      end
    end
  end
end
