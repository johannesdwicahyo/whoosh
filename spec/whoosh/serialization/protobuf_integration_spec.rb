# spec/whoosh/serialization/protobuf_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Protobuf serialization integration" do
  it "Negotiator routes to Protobuf for application/protobuf" do
    expect(Whoosh::Serialization::Negotiator.for_accept("application/protobuf")).to eq(Whoosh::Serialization::Protobuf)
  end

  it "Negotiator routes to Protobuf for application/x-protobuf" do
    expect(Whoosh::Serialization::Negotiator.for_accept("application/x-protobuf")).to eq(Whoosh::Serialization::Protobuf)
  end

  it "reports availability" do
    expect([true, false]).to include(Whoosh::Serialization::Protobuf.available?)
  end

  it "has correct content type" do
    expect(Whoosh::Serialization::Protobuf.content_type).to eq("application/protobuf")
  end

  it "raises DependencyError without gem" do
    original = Whoosh::Serialization::Protobuf.instance_variable_get(:@available)
    Whoosh::Serialization::Protobuf.instance_variable_set(:@available, false)
    expect { Whoosh::Serialization::Protobuf.encode({}) }.to raise_error(Whoosh::Errors::DependencyError)
    Whoosh::Serialization::Protobuf.instance_variable_set(:@available, original)
  end
end
