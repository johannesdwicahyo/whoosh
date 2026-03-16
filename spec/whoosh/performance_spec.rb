# spec/whoosh/performance_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Performance do
  describe ".enable_yjit!" do
    it "does not crash" do
      expect { Whoosh::Performance.enable_yjit! }.not_to raise_error
    end
  end

  describe ".yjit_enabled?" do
    it "returns a boolean" do
      expect([true, false]).to include(Whoosh::Performance.yjit_enabled?)
    end
  end

  describe ".optimize!" do
    it "runs without error" do
      expect { Whoosh::Performance.optimize! }.not_to raise_error
    end

    it "detects JSON engine" do
      Whoosh::Performance.optimize!
      expect(Whoosh::Serialization::Json.engine).not_to be_nil
    end
  end
end
