module Whoosh
  # A thin, lazy wrapper over the Rack env. Reads and parses only what an
  # endpoint needs, and enforces body size and content-type rules.
  class Request
    SAFE_REQUEST_ID = /\A[\w\-.:]{1,128}\z/
    JSON_TYPE = %r{\Aapplication/([\w.+-]+\+)?json\s*(;|\z)}i

    attr_reader :env
    attr_accessor :user_id_for_limits

    def initialize(env, config = Whoosh.config)
      @env = env
      @config = config
    end

    def request_method = @env["REQUEST_METHOD"].to_s.upcase
    def head? = request_method == "HEAD"
    def https? = @env["rack.url_scheme"] == "https" || @env["HTTP_X_FORWARDED_PROTO"] == "https"

    # Path relative to where the app is mounted (Rails/Sinatra strip the
    # mount point into SCRIPT_NAME).
    def path
      @path ||= begin
        p = @env["PATH_INFO"].to_s
        p = "/#{p}" unless p.start_with?("/")
        p.length > 1 ? p.chomp("/") : p
      end
    end

    def script_name = @env["SCRIPT_NAME"].to_s

    def header(name)
      key = name.to_s.upcase.tr("-", "_")
      return @env["CONTENT_TYPE"] if key == "CONTENT_TYPE"
      return @env["CONTENT_LENGTH"] if key == "CONTENT_LENGTH"

      @env["HTTP_#{key}"]
    end

    def origin = header("origin")
    def content_type = @env["CONTENT_TYPE"].to_s

    def request_id
      @request_id ||= begin
        incoming = header(@config.request_id_header) || @env["action_dispatch.request_id"]
        incoming.is_a?(String) && incoming.match?(SAFE_REQUEST_ID) ? incoming : SecureRandom.uuid
      end
    end

    # Client address. Trusts Rails' RemoteIp result when mounted in Rails,
    # otherwise the socket address; never reads X-Forwarded-For directly.
    def ip
      (@env["action_dispatch.remote_ip"] || @env["REMOTE_ADDR"]).to_s
    end

    # "Authorization: Bearer <token>" -> "<token>"
    def bearer_token
      value = header("authorization").to_s
      match = value.match(/\ABearer\s+([A-Za-z0-9\-._~+\/]+=*)\s*\z/)
      match && match[1]
    end

    # Query string as a Hash. `a=1&b[]=2&b[]=3` -> {"a"=>"1", "b"=>["2","3"]}.
    # Bracketed keys other than [] aren't expanded into nested hashes.
    def query
      @query ||= begin
        out = {}
        qs = @env["QUERY_STRING"].to_s
        raise BadRequest.new("The query string is too long.") if qs.bytesize > 16_384

        URI.decode_www_form(qs).each do |key, value|
          if key.end_with?("[]")
            (out[key.delete_suffix("[]")] ||= []) << value
          else
            out[key] = value
          end
        end
        raise BadRequest.new("The query string has too many parameters.") if out.size > 200

        out
      rescue ArgumentError
        raise BadRequest.new("The query string is malformed.")
      end
    end

    def raw_body
      return @raw_body if defined?(@raw_body)

      max = @config.max_body_size
      length = @env["CONTENT_LENGTH"].to_s
      raise PayloadTooLarge if length.match?(/\A\d+\z/) && length.to_i > max

      input = @env["rack.input"]
      body = input ? input.read(max + 1).to_s : ""
      input.rewind if input.respond_to?(:rewind)
      raise PayloadTooLarge if body.bytesize > max

      @raw_body = body
    end

    # Parsed JSON body. Must be an object. Empty bodies parse as {}.
    def json
      return @json if defined?(@json)

      body = raw_body
      if body.strip.empty?
        @json = {}
      else
        raise UnsupportedMediaType unless content_type.match?(JSON_TYPE)

        parsed = Whoosh::JSON.parse(body, max_depth: @config.max_json_depth)
        raise BadRequest.new("The JSON body must be an object.") unless parsed.is_a?(Hash)

        @json = Whoosh::JSON.check_size!(parsed, @config.max_json_keys)
      end
    end

    def body? = %w[POST PUT PATCH DELETE].include?(request_method)
  end
end
