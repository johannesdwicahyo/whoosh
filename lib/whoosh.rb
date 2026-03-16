# frozen_string_literal: true

require_relative "whoosh/version"

module Whoosh
  autoload :App,                 "whoosh/app"
  autoload :Config,              "whoosh/config"
  autoload :Database,            "whoosh/database"
  autoload :DependencyInjection, "whoosh/dependency_injection"
  autoload :Endpoint,            "whoosh/endpoint"
  autoload :Errors,              "whoosh/errors"
  autoload :Logger,              "whoosh/logger"
  autoload :Request,             "whoosh/request"
  autoload :Response,            "whoosh/response"
  autoload :Router,              "whoosh/router"
  autoload :Schema,              "whoosh/schema"
  autoload :Shutdown,            "whoosh/shutdown"
  autoload :Types,               "whoosh/types"
  autoload :Performance,         "whoosh/performance"

  module Auth
    autoload :ApiKey,         "whoosh/auth/api_key"
    autoload :Jwt,            "whoosh/auth/jwt"
    autoload :OAuth2,         "whoosh/auth/oauth2"
    autoload :RateLimiter,    "whoosh/auth/rate_limiter"
    autoload :TokenTracker,   "whoosh/auth/token_tracker"
    autoload :AccessControl,  "whoosh/auth/access_control"
  end

  module MCP
    autoload :Server,        "whoosh/mcp/server"
    autoload :Client,        "whoosh/mcp/client"
    autoload :ClientManager, "whoosh/mcp/client_manager"
    autoload :Protocol,      "whoosh/mcp/protocol"
  end

  module Middleware
    autoload :Stack,           "whoosh/middleware/stack"
    autoload :Cors,            "whoosh/middleware/cors"
    autoload :RequestLogger,   "whoosh/middleware/request_logger"
    autoload :SecurityHeaders, "whoosh/middleware/security_headers"
    autoload :RequestLimit,    "whoosh/middleware/request_limit"
    autoload :PluginHooks,     "whoosh/middleware/plugin_hooks"
  end

  module Streaming
    autoload :SSE,       "whoosh/streaming/sse"
    autoload :WebSocket, "whoosh/streaming/websocket"
    autoload :LlmStream, "whoosh/streaming/llm_stream"
  end

  module OpenAPI
    autoload :Generator,       "whoosh/openapi/generator"
    autoload :UI,              "whoosh/openapi/ui"
    autoload :SchemaConverter, "whoosh/openapi/schema_converter"
  end

  module Serialization
    autoload :Json,       "whoosh/serialization/json"
    autoload :Msgpack,    "whoosh/serialization/msgpack"
    autoload :Protobuf,   "whoosh/serialization/protobuf"
    autoload :Negotiator, "whoosh/serialization/negotiator"
  end

  module Plugins
    autoload :Registry, "whoosh/plugins/registry"
    autoload :Base,     "whoosh/plugins/base"
  end
end
