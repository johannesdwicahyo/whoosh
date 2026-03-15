# frozen_string_literal: true

require "spec_helper"

class OpenAPITestSchema < Whoosh::Schema
  field :name,        String,  required: true, desc: "User name"
  field :email,       String,  required: true
  field :age,         Integer, min: 0, max: 150
  field :temperature, Float,   default: 0.7
  field :active,      Whoosh::Types::Bool, default: true
end

class OpenAPINestedSchema < Whoosh::Schema
  field :user,    OpenAPITestSchema, required: true
  field :comment, String
end

RSpec.describe Whoosh::OpenAPI::SchemaConverter do
  describe ".convert" do
    it "converts a schema to OpenAPI format" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPITestSchema)
      expect(result[:type]).to eq("object")
      expect(result[:properties][:name][:type]).to eq("string")
      expect(result[:properties][:name][:description]).to eq("User name")
      expect(result[:required]).to include(:name, :email)
    end

    it "includes integer type with min/max" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPITestSchema)
      age = result[:properties][:age]
      expect(age[:type]).to eq("integer")
      expect(age[:minimum]).to eq(0)
      expect(age[:maximum]).to eq(150)
    end

    it "includes float type with default" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPITestSchema)
      expect(result[:properties][:temperature][:type]).to eq("number")
      expect(result[:properties][:temperature][:default]).to eq(0.7)
    end

    it "converts boolean type" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPITestSchema)
      expect(result[:properties][:active][:type]).to eq("boolean")
    end

    it "handles nested schemas" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPINestedSchema)
      expect(result[:properties][:user][:type]).to eq("object")
      expect(result[:properties][:user][:properties][:name][:type]).to eq("string")
    end
  end

  describe ".type_for" do
    it "maps Ruby types to OpenAPI types" do
      expect(Whoosh::OpenAPI::SchemaConverter.type_for(String)).to eq("string")
      expect(Whoosh::OpenAPI::SchemaConverter.type_for(Integer)).to eq("integer")
      expect(Whoosh::OpenAPI::SchemaConverter.type_for(Float)).to eq("number")
    end
  end
end
