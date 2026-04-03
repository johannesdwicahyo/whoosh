# spec/whoosh/client_gen/dependency_checker_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/client_gen/dependency_checker"

RSpec.describe Whoosh::ClientGen::DependencyChecker do
  describe ".check" do
    it "returns success for htmx (no dependencies)" do
      result = described_class.check(:htmx)
      expect(result[:ok]).to be true
    end

    it "returns required dependencies for react_spa" do
      result = described_class.check(:react_spa)
      expect(result[:dependencies]).to include("node")
    end

    it "returns required dependencies for ios" do
      result = described_class.check(:ios)
      expect(result[:dependencies]).to include("xcodebuild")
    end

    it "returns required dependencies for flutter" do
      result = described_class.check(:flutter)
      expect(result[:dependencies]).to include("flutter")
    end

    it "returns required dependencies for telegram_bot" do
      result = described_class.check(:telegram_bot)
      expect(result[:dependencies]).to include("ruby")
    end
  end

  describe ".dependency_for" do
    it "returns the check command for each client type" do
      expect(described_class.dependency_for(:react_spa)).to eq([{ cmd: "node", check: "node --version", min_version: "18" }])
      expect(described_class.dependency_for(:expo)).to include(hash_including(cmd: "node"))
    end
  end
end
