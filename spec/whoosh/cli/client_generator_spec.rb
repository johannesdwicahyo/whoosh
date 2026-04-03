# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/cli/client_generator"

RSpec.describe Whoosh::CLI::ClientGenerator do
  describe ".client_types" do
    it "lists all supported client types" do
      types = described_class.client_types
      expect(types).to include(:react_spa, :expo, :ios, :flutter, :htmx, :telegram_bot, :telegram_mini_app)
    end
  end

  describe "#run" do
    it "rejects unknown client types" do
      expect {
        described_class.new(type: "android", oauth: false, dir: nil).validate!
      }.to raise_error(Whoosh::ClientGen::Error, /Unknown client type/)
    end

    it "accepts valid client types" do
      %w[react_spa expo ios flutter htmx telegram_bot telegram_mini_app].each do |type|
        generator = described_class.new(type: type, oauth: false, dir: nil)
        expect { generator.validate! }.not_to raise_error
      end
    end
  end

  describe "#default_output_dir" do
    it "returns clients/<type> by default" do
      gen = described_class.new(type: "react_spa", oauth: false, dir: nil)
      expect(gen.default_output_dir).to eq("clients/react_spa")
    end

    it "uses custom dir when provided" do
      gen = described_class.new(type: "react_spa", oauth: false, dir: "my_frontend")
      expect(gen.output_dir).to eq("my_frontend")
    end
  end

  describe "#introspect_or_fallback" do
    it "returns fallback IR when no app exists" do
      Dir.mktmpdir do |dir|
        gen = described_class.new(type: "react_spa", oauth: false, dir: nil, root: dir)
        result = gen.introspect_or_fallback
        expect(result[:mode]).to eq(:fallback)
      end
    end
  end
end
