module Whoosh
  # One endpoint, built from the block given to get/post/put/patch/delete.
  # `finalize!` enforces the secure-by-default rules when the API is defined:
  # every endpoint says who may call it, and what it returns.
  class Endpoint
    VERBS = %w[GET POST PUT PATCH DELETE].freeze
    PATH_PARAM = /:([a-z_][a-z0-9_]*)/

    attr_reader :verb, :path, :api, :params_schema, :returns_schema, :pagination, :handler,
                :authorizer, :idempotency, :status, :docs

    def initialize(api, verb, path)
      @api = api
      @verb = verb
      @path = path
      @public = false
      @authorizer = nil
      @params_schema = nil
      @returns_schema = nil
      @returns_set = false
      @many = false
      @status = verb == "POST" ? 201 : 200
      @pagination = nil
      @idempotency = nil
      @rate_limit = :default
      @handler = nil
      @docs = {}
    end

    def id = "#{verb} #{path}"
    def public? = @public
    def many? = @many || !@pagination.nil?
    def no_content? = @returns_set && @returns_schema.nil?
    def path_params = path.scan(PATH_PARAM).flatten

    # ---- DSL (evaluated inside the endpoint block) -------------------------

    # Anyone may call this endpoint, signed in or not.
    def public!
      @public = true
    end

    # Who may call this endpoint. Runs before the handler with the current
    # user (never nil unless public!) and the parsed params. Falsey -> 403.
    #   authorize { |user| user.admin? }
    #   authorize { |user, p| user.store_ids.include?(p[:store_id]) }
    def authorize(&block)
      raise DefinitionError, "#{id}: authorize needs a block" unless block

      @authorizer = block
    end

    # Accepted input: path params, query string and JSON body, merged.
    # Undeclared keys never reach the handler.
    #   params do
    #     required :id, :integer
    #     optional :status, :string, enum: %w[pending paid]
    #   end
    #   params OrderInput
    def params(schema = nil, &block)
      @params_schema = schema || Schema.build("#{schema_prefix}Params", &block)
    end

    # The response shape. Only declared fields are serialized.
    #   returns OrderSchema
    #   returns OrderSchema, many: true
    #   returns OrderSchema, status: 202
    #   returns nil                 # 204 No Content
    #   returns { field :ok, :boolean }
    def returns(schema = :__block, many: false, status: nil, &block)
      @returns_set = true
      @many = many
      @status = status if status
      if schema.nil?
        @returns_schema = nil
        @status = 204
      elsif schema == :__block
        raise DefinitionError, "#{id}: returns needs a schema or a block" unless block

        @returns_schema = Schema.build("#{schema_prefix}Response", &block)
      else
        unless schema.is_a?(Class) && schema <= Schema
          raise DefinitionError, "#{id}: returns expects a Whoosh::Schema subclass, got #{schema.inspect}"
        end

        @returns_schema = schema
      end
    end

    #   paginate                      # cursor on id, ascending
    #   paginate :cursor, by: :created_at, order: :desc
    #   paginate :offset
    def paginate(style = :cursor, by: :id, order: :asc)
      @pagination = Pagination.new(style, by: by, order: order)
    end

    # Replay responses for repeated Idempotency-Key headers.
    #   idempotent                   # header optional
    #   idempotent required: true    # header required (payments)
    def idempotent(required: false)
      @idempotency = { required: required }
    end

    #   rate_limit 10, per: 60
    #   rate_limit false
    def rate_limit(limit, per: 60)
      @rate_limit = limit == false ? false : [Integer(limit), Integer(per)]
    end

    def handle(&block)
      raise DefinitionError, "#{id}: handle needs a block" unless block

      @handler = block
    end

    def summary(text) = @docs[:summary] = text
    def description(text) = @docs[:description] = text
    def tags(*names) = @docs[:tags] = names.flatten.map(&:to_s)
    def deprecated! = @docs[:deprecated] = true

    # ---- Validation --------------------------------------------------------

    def finalize!
      problems = []
      problems << "has no handler (add `handle { |params| ... }`)" unless @handler
      unless @public || @authorizer
        problems << "has no access rule (add `authorize { |user| ... }`, or `public!` for anonymous access)"
      end
      problems << "doesn't declare its response (add `returns SomeSchema`, or `returns nil` for 204)" unless @returns_set
      if @pagination && @returns_schema.nil?
        problems << "is paginated but returns nothing"
      end
      raise DefinitionError, "#{api.name || 'API'} #{id} #{problems.join('; ')}" if problems.any?

      add_path_params_to_schema
      freeze_definition
      self
    end

    def effective_rate_limit(config)
      @rate_limit == :default ? config.rate_limit : @rate_limit
    end

    private

    def schema_prefix
      "#{api.name.to_s.gsub('::', '')}#{verb.capitalize}#{path.gsub(/[^a-zA-Z0-9]+/, '_').split('_').map(&:capitalize).join}"
    end

    # Path params are always accepted; declare them in `params` to type them.
    def add_path_params_to_schema
      names = path_params
      return if names.empty?

      @params_schema ||= Schema.build("#{schema_prefix}Params")
      missing = names.reject { |n| @params_schema.fields.key?(n.to_sym) }
      return if missing.empty?

      @params_schema = @params_schema.build(@params_schema.schema_name) do
        missing.each { |n| required n.to_sym, :string, max_length: 512 }
      end
    end

    def freeze_definition
      @docs.freeze
    end
  end
end
