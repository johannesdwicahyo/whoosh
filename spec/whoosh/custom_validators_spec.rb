# spec/whoosh/custom_validators_spec.rb
# frozen_string_literal: true
require "spec_helper"

class EmailSchema < Whoosh::Schema
  field :email, String, required: true

  validate_with do |data, errors|
    if data[:email] && !data[:email].include?("@")
      errors << { field: :email, message: "must contain @" }
    end
  end
end

class AgeSchema < Whoosh::Schema
  field :age, Integer, required: true

  validate_with do |data, errors|
    errors << { field: :age, message: "must be 18+" } if data[:age] && data[:age] < 18
  end
end

RSpec.describe "Custom schema validators" do
  it "runs custom validator" do
    result = EmailSchema.validate({ email: "invalid" })
    expect(result).not_to be_success
    expect(result.errors.first[:message]).to include("@")
  end

  it "passes valid data" do
    result = EmailSchema.validate({ email: "a@b.com" })
    expect(result).to be_success
  end

  it "supports multiple validators" do
    result = AgeSchema.validate({ age: 10 })
    expect(result).not_to be_success
  end
end
