# frozen_string_literal: true

require_relative "../schemas/user"

class UsersEndpoint < Whoosh::Endpoint
  post "/users", request: CreateUserRequest

  def call(req)
    { id: SecureRandom.uuid, name: req.body[:name], email: req.body[:email] }
  end
end
