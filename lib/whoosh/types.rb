# frozen_string_literal: true

require "dry-types"

module Whoosh
  module Types
    include Dry.Types()

    Bool = Types::Params::Bool
  end
end
