# lib/whoosh/job.rb
# frozen_string_literal: true

module Whoosh
  class Job
    class << self
      def inject(*names)
        @dependencies = names
      end

      def dependencies
        @dependencies || []
      end

      def perform_async(**args)
        Jobs.enqueue(self, **args)
      end
    end

    def perform(**args)
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end
  end
end
