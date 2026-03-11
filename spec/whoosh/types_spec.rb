# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Types do
  describe "Bool" do
    it "coerces true string" do
      expect(Whoosh::Types::Bool["true"]).to be true
    end

    it "coerces false string" do
      expect(Whoosh::Types::Bool["false"]).to be false
    end

    it "accepts true" do
      expect(Whoosh::Types::Bool[true]).to be true
    end

    it "accepts false" do
      expect(Whoosh::Types::Bool[false]).to be false
    end

    it "rejects invalid values" do
      expect { Whoosh::Types::Bool["invalid"] }.to raise_error(Dry::Types::CoercionError)
    end
  end

  describe "String" do
    it "is available" do
      expect(Whoosh::Types::String["hello"]).to eq("hello")
    end
  end

  describe "Integer" do
    it "coerces string to integer" do
      expect(Whoosh::Types::Coercible::Integer["42"]).to eq(42)
    end
  end
end
