# frozen_string_literal: true

module Whoosh
  module Plugins
    class Base
      class << self
        def gem_name(name = nil)
          if name
            @gem_name = name
          else
            @gem_name
          end
        end

        def accessor_name(name = nil)
          if name
            @accessor_name = name
          else
            @accessor_name
          end
        end

        def middleware?
          false
        end

        def before_request(req, config)
          # Override in subclass
        end

        def after_response(res, config)
          # Override in subclass
        end

        def initialize_plugin(config)
          # Override in subclass — return the plugin instance
          nil
        end
      end
    end
  end
end
