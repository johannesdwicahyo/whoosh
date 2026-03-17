# frozen_string_literal: true

class HealthResponse < Whoosh::Schema
  field :status, String, required: true, desc: "Health status"
  field :version, String, desc: "API version"
end
