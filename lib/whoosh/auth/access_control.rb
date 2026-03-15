# frozen_string_literal: true

module Whoosh
  module Auth
    class AccessControl
      def initialize
        @roles = {}
      end

      def role(name, models: [])
        @roles[name] = models.dup.freeze
      end

      def check!(role, model)
        allowed = @roles[role]
        unless allowed && allowed.include?(model)
          raise Errors::ForbiddenError, "Model '#{model}' not allowed for role '#{role}'"
        end
      end

      def models_for(role)
        @roles[role] || []
      end
    end
  end
end
