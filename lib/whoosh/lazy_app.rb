module Whoosh
  # Resolves API classes by name on each request, so Rails code reloading
  # picks up edited API files without restarting the server. Rebuilds the
  # router only when a class was actually reloaded.
  #
  #   mount Whoosh.app("OrdersApi", "CustomersApi"), at: "/api"
  class LazyApp
    def initialize(names, **options)
      @names = names.map(&:to_s)
      @options = options
      @mutex = Mutex.new
      @apis = nil
      @app = nil
    end

    def call(env)
      current = @names.map { |n| Object.const_get(n) }
      app = @mutex.synchronize do
        if @apis.nil? || current.zip(@apis).any? { |a, b| !a.equal?(b) }
          @apis = current
          @app = App.new(current, **@options)
        end
        @app
      end
      app.call(env)
    end
  end
end
