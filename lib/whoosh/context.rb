module Whoosh
  # The object `authorize` and `handle` blocks run in. A fresh one per
  # request; the API's `helpers` are mixed into its class.
  class Context
    attr_reader :request, :params, :current_user, :endpoint

    def initialize(request, endpoint, current_user)
      @request = request
      @endpoint = endpoint
      @current_user = current_user
      @params = {}.freeze
      @response_headers = {}
      @status = nil
    end

    def assign_params(params)
      @params = params
    end

    # Override the response status: `status 202`.
    def status(code = nil)
      return @status if code.nil?

      @status = Integer(code)
    end

    # Add a response header: `header "location", "/v1/orders/#{order.id}"`.
    def header(name, value)
      key = name.to_s.downcase
      raise ArgumentError, "invalid header value" if value.to_s.match?(/[\r\n]/)

      @response_headers[key] = value.to_s
    end

    def response_headers = @response_headers

    # Stop with an error response. All of these render the standard envelope.
    def not_found!(message = nil) = raise(NotFound.new(message))
    def forbidden!(message = nil) = raise(Forbidden.new(message))
    def unauthorized!(message = nil) = raise(Unauthorized.new(message))
    def conflict!(message = nil, code: nil) = raise(Conflict.new(message, code: code))
    def bad_request!(message = nil, code: nil) = raise(BadRequest.new(message, code: code))

    # Field-level errors, same shape as schema validation:
    #   invalid!(quantity: "is more than the stock left")
    def invalid!(errors, message = nil)
      details = errors.to_h.transform_keys(&:to_s).transform_values { |v| Array(v) }
      raise ValidationError.new(details, message)
    end

    # Any status and code: error!(402, "payment_required", "Top up your balance first.")
    def error!(status, code, message, details: nil)
      raise HTTPError.new(message, status: status, code: code, details: details)
    end
  end
end
