# frozen_string_literal: true

require "spec_helper"
require "whoosh/serialization/protobuf"

RSpec.describe Whoosh::Serialization::Protobuf do
  describe ".content_type" do
    it "returns application/protobuf" do
      expect(Whoosh::Serialization::Protobuf.content_type).to eq("application/protobuf")
    end
  end

  describe ".available?" do
    it "returns a boolean" do
      expect(Whoosh::Serialization::Protobuf.available?).to be(true).or be(false)
    end
  end

  describe ".encode" do
    it "raises DependencyError if gem not available" do
      original = Whoosh::Serialization::Protobuf.instance_variable_get(:@available)
      Whoosh::Serialization::Protobuf.instance_variable_set(:@available, false)
      expect { Whoosh::Serialization::Protobuf.encode({}) }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Serialization::Protobuf.instance_variable_set(:@available, original)
    end
  end
end
