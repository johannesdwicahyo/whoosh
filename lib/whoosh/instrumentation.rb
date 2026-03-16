# lib/whoosh/instrumentation.rb
# frozen_string_literal: true

module Whoosh
  class Instrumentation
    def initialize
      @subscribers = Hash.new { |h, k| h[k] = [] }
    end

    def on(event, &block)
      @subscribers[event] << block
    end

    def emit(event, data = {})
      @subscribers[event].each do |subscriber|
        subscriber.call(data)
      rescue => e
        # Don't let subscriber errors crash the app
      end
    end
  end
end
