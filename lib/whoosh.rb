require "json"
require "securerandom"
require "bigdecimal"
require "date"
require "time"
require "openssl"
require "uri"
require "digest"

require "whoosh/version"
require "whoosh/errors"
require "whoosh/configuration"
require "whoosh/json"
require "whoosh/types"
require "whoosh/schema"
require "whoosh/router"
require "whoosh/request"
require "whoosh/stores/memory"
require "whoosh/stores/cache"
require "whoosh/rate_limiter"
require "whoosh/idempotency"
require "whoosh/pagination"
require "whoosh/endpoint"
require "whoosh/context"
require "whoosh/openapi"
require "whoosh/app"
require "whoosh/lazy_app"
require "whoosh/api"

# Whoosh: an opinionated, secure-by-default JSON API framework for Rack.
#
#   class OrdersAPI < Whoosh::API
#     version 1
#
#     get "/orders/:id" do
#       authorize { |user| user.staff? }
#       params { required :id, :integer }
#       returns OrderSchema
#       handle { |p| Order.find(p[:id]) }
#     end
#   end
#
#   # Rails:      mount OrdersAPI => "/api"
#   # config.ru:  run OrdersAPI
module Whoosh
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    # Combine several API classes into one Rack app.
    #   run Whoosh.app(OrdersAPI, CustomersAPI)
    # Pass class names as strings in Rails so code reloading works:
    #   mount Whoosh.app("OrdersApi", "CustomersApi"), at: "/api"
    def app(*apis, **options)
      apis = apis.flatten
      apis.any? { |a| a.is_a?(String) } ? LazyApp.new(apis, **options) : App.new(apis, **options)
    end

    # Tests use this to start from a clean slate.
    def reset_config!
      @config = Configuration.new
    end
  end
end

require "whoosh/railtie" if defined?(Rails::Railtie)
