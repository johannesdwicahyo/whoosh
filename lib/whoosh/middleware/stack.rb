# frozen_string_literal: true

module Whoosh
  module Middleware
    class Stack
      def initialize
        @middlewares = []
      end

      def use(middleware, *args, **kwargs)
        @middlewares << { klass: middleware, args: args, kwargs: kwargs }
      end

      def build(app)
        @middlewares.reverse.reduce(app) do |next_app, entry|
          if entry[:kwargs].empty?
            entry[:klass].new(next_app, *entry[:args])
          else
            entry[:klass].new(next_app, *entry[:args], **entry[:kwargs])
          end
        end
      end
    end
  end
end
