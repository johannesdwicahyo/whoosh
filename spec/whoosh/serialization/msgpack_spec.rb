# frozen_string_literal: true

require "spec_helper"
require "whoosh/serialization/msgpack"

RSpec.describe Whoosh::Serialization::Msgpack do
  describe ".content_type" do
    it "returns application/msgpack" do
      expect(Whoosh::Serialization::Msgpack.content_type).to eq("application/msgpack")
    end
  end

  describe ".available?" do
    it "returns a boolean" do
      expect(Whoosh::Serialization::Msgpack.available?).to be(true).or be(false)
    end
  end

  describe ".encode" do
    it "raises DependencyError if gem not available" do
      original = Whoosh::Serialization::Msgpack.instance_variable_get(:@available)
      Whoosh::Serialization::Msgpack.instance_variable_set(:@available, false)
      expect { Whoosh::Serialization::Msgpack.encode({}) }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Serialization::Msgpack.instance_variable_set(:@available, original)
    end
  end
end
