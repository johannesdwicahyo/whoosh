# frozen_string_literal: true

require "spec_helper"

# Test schemas
class TestUserSchema < Whoosh::Schema
  field :name,  String,  required: true, desc: "User name"
  field :email, String,  required: true, desc: "User email"
  field :age,   Integer, min: 0, max: 150
  field :active, Whoosh::Types::Bool, default: true
  field :role,  String,  default: "user"
end

class TestAddressSchema < Whoosh::Schema
  field :street, String, required: true
  field :city,   String, required: true
end

class TestProfileSchema < Whoosh::Schema
  field :user,    TestUserSchema, required: true
  field :address, TestAddressSchema
end

RSpec.describe Whoosh::Schema do
  describe ".validate" do
    it "passes with valid data" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com", age: 30 })
      expect(result).to be_success
      expect(result.data[:name]).to eq("Alice")
    end

    it "applies defaults" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com" })
      expect(result.data[:role]).to eq("user")
    end

    it "fails with missing required fields" do
      result = TestUserSchema.validate({ age: 30 })
      expect(result).not_to be_success
      expect(result.errors).to include(
        hash_including(field: :name, message: a_string_matching(/required|missing|filled/i))
      )
    end

    it "fails with out-of-range values" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com", age: -5 })
      expect(result).not_to be_success
      expect(result.errors).to include(
        hash_including(field: :age)
      )
    end

    it "coerces string to integer" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com", age: "25" })
      expect(result).to be_success
      expect(result.data[:age]).to eq(25)
    end

    it "validates Bool field" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com", active: "true" })
      expect(result).to be_success
      expect(result.data[:active]).to be true
    end

    it "applies Bool default" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com" })
      expect(result).to be_success
      expect(result.data[:active]).to be true
    end
  end

  describe "nested schemas" do
    it "validates nested data" do
      result = TestProfileSchema.validate({
        user: { name: "Alice", email: "a@b.com" },
        address: { street: "123 Main", city: "NYC" }
      })
      expect(result).to be_success
      expect(result.data[:user][:name]).to eq("Alice")
    end

    it "fails on invalid nested data" do
      result = TestProfileSchema.validate({
        user: { email: "a@b.com" }
      })
      expect(result).not_to be_success
    end
  end

  describe ".fields" do
    it "returns field definitions" do
      fields = TestUserSchema.fields
      expect(fields[:name]).to include(type: String, required: true, desc: "User name")
      expect(fields[:role]).to include(default: "user")
    end
  end

  describe ".to_h (serialization)" do
    it "serializes data to hash" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com" })
      hash = TestUserSchema.serialize(result.data)
      expect(hash).to eq({ name: "Alice", email: "a@b.com", age: nil, role: "user", active: true })
    end
  end
end
