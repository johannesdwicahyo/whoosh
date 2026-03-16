# frozen_string_literal: true

class CreateUserRequest < Whoosh::Schema
  field :name, String, required: true, desc: "User name"
  field :email, String, required: true, desc: "Email address"
end
