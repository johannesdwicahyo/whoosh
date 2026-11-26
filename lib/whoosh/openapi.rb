module Whoosh
  # Builds an OpenAPI 3.1 document from endpoint definitions. Named schema
  # classes become reusable components; inline ones are expanded in place.
  class OpenAPI
    def initialize(apis, server_url: nil, title: nil, version: nil, error_format: Whoosh.config.error_format)
      @problem = error_format == :problem
      @apis = apis
      @server_url = server_url
      @title = title
      @version = version
      @components = {}
    end

    def document
      paths = {}
      @apis.each do |api|
        api.endpoints.each do |endpoint|
          key = endpoint.path.gsub(Endpoint::PATH_PARAM) { "{#{Regexp.last_match(1)}}" }
          (paths[key] ||= {})[endpoint.verb.downcase] = operation(endpoint)
        end
      end

      info = @apis.map(&:info).reduce({}, :merge)
      doc = {
        "openapi" => "3.1.0",
        "info" => {
          "title" => @title || info["title"] || "API",
          "version" => @version || info["version"] || "1.0.0"
        },
        "paths" => paths,
        "components" => {
          "schemas" => @components.merge("Error" => error_schema),
          "securitySchemes" => { "bearer" => { "type" => "http", "scheme" => "bearer" } }
        }
      }
      doc["info"]["description"] = info["description"] if info["description"]
      doc["servers"] = [{ "url" => @server_url }] if @server_url && !@server_url.empty?
      doc
    end

    private

    def operation(endpoint)
      op = {
        "operationId" => operation_id(endpoint),
        "responses" => responses(endpoint)
      }
      op["summary"] = endpoint.docs[:summary] if endpoint.docs[:summary]
      op["description"] = endpoint.docs[:description] if endpoint.docs[:description]
      op["tags"] = endpoint.docs[:tags] if endpoint.docs[:tags]
      op["deprecated"] = true if endpoint.docs[:deprecated]
      op["security"] = endpoint.public? ? [] : [{ "bearer" => [] }]

      parameters, body = split_params(endpoint)
      parameters += pagination_parameters(endpoint) if endpoint.pagination
      if endpoint.idempotency
        parameters << { "name" => "Idempotency-Key", "in" => "header", "required" => endpoint.idempotency[:required],
                        "schema" => { "type" => "string", "minLength" => 8, "maxLength" => 255 } }
      end
      op["parameters"] = parameters unless parameters.empty?
      if body
        op["requestBody"] = { "required" => body.key?("required"),
                              "content" => { "application/json" => { "schema" => body } } }
      end
      op
    end

    # Path params go in the path; for GET/DELETE the rest are query params,
    # otherwise they're the JSON body.
    def split_params(endpoint)
      schema = endpoint.params_schema
      return [[], nil] unless schema

      json = schema.to_json_schema(ref: method(:ref))
      path_names = endpoint.path_params
      parameters = path_names.map do |name|
        { "name" => name, "in" => "path", "required" => true, "schema" => json["properties"][name] || { "type" => "string" } }
      end

      rest = json["properties"].reject { |k, _| path_names.include?(k) }
      required = Array(json["required"]) - path_names
      return [parameters, nil] if rest.empty?

      if %w[GET DELETE].include?(endpoint.verb)
        rest.each do |name, prop|
          parameters << { "name" => name, "in" => "query", "required" => required.include?(name), "schema" => prop }
        end
        [parameters, nil]
      else
        body = { "type" => "object", "properties" => rest }
        body["required"] = required unless required.empty?
        [parameters, body]
      end
    end

    def pagination_parameters(endpoint)
      second = endpoint.pagination.style == :cursor ? { "name" => "cursor", "schema" => { "type" => "string" } } : { "name" => "page", "schema" => { "type" => "integer", "minimum" => 1 } }
      [
        { "name" => "limit", "in" => "query", "schema" => { "type" => "integer", "minimum" => 1 } },
        second.merge("in" => "query")
      ]
    end

    def responses(endpoint)
      out = {}
      if endpoint.no_content?
        out[endpoint.status.to_s] = { "description" => "No content" }
      else
        data = ref(endpoint.returns_schema)
        data = { "type" => "array", "items" => data } if endpoint.many?
        props = { "data" => data }
        if endpoint.pagination
          props["meta"] = { "type" => "object", "properties" => pagination_meta(endpoint) }
        end
        out[endpoint.status.to_s] = {
          "description" => "Success",
          "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => props, "required" => ["data"] } } }
        }
      end
      error_codes(endpoint).each do |code, description|
        out[code] = { "description" => description,
                      "content" => { error_media_type => { "schema" => { "$ref" => "#/components/schemas/Error" } } } }
      end
      out
    end

    def pagination_meta(endpoint)
      base = { "limit" => { "type" => "integer" } }
      if endpoint.pagination.style == :cursor
        base.merge("next_cursor" => { "type" => %w[string null] })
      else
        base.merge("page" => { "type" => "integer" }, "next_page" => { "type" => %w[integer null] })
      end
    end

    def error_codes(endpoint)
      codes = {}
      codes["401"] = "Not signed in" unless endpoint.public?
      codes["403"] = "Not allowed" if endpoint.authorizer
      codes["404"] = "Not found" unless endpoint.many? || endpoint.no_content?
      codes["422"] = "Invalid input" if endpoint.params_schema || endpoint.pagination
      codes["429"] = "Rate limited" if endpoint.effective_rate_limit(Whoosh.config)
      codes
    end

    def ref(schema)
      name = schema.schema_name
      return schema.to_json_schema(ref: method(:ref)) if name.nil? || schema.name.nil?

      key = name.gsub("::", "")
      unless @components.key?(key)
        @components[key] = {} # placeholder stops recursion on self-referencing schemas
        @components[key] = schema.to_json_schema(ref: method(:ref))
      end
      { "$ref" => "#/components/schemas/#{key}" }
    end

    def operation_id(endpoint)
      parts = endpoint.path.split("/").reject(&:empty?).map { |s| s.start_with?(":") ? "by_#{s[1..]}" : s }
      ([endpoint.verb.downcase] + parts).join("_").gsub(/[^a-zA-Z0-9_]/, "_")
    end

    def error_media_type = @problem ? "application/problem+json" : "application/json"

    # RFC 9457 problem details, plus the extension members Whoosh adds.
    def problem_schema
      {
        "type" => "object",
        "required" => %w[type title status detail code request_id],
        "properties" => {
          "type" => { "type" => "string" },
          "title" => { "type" => "string" },
          "status" => { "type" => "integer" },
          "detail" => { "type" => "string" },
          "code" => { "type" => "string" },
          "errors" => { "type" => "object" },
          "request_id" => { "type" => "string" }
        }
      }
    end

    def error_schema
      return problem_schema if @problem

      {
        "type" => "object",
        "required" => ["error"],
        "properties" => {
          "error" => {
            "type" => "object",
            "required" => %w[code message request_id],
            "properties" => {
              "code" => { "type" => "string" },
              "message" => { "type" => "string" },
              "details" => { "type" => "object" },
              "request_id" => { "type" => "string" }
            }
          }
        }
      }
    end
  end
end
