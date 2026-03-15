# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Logger do
  let(:output) { StringIO.new }

  describe "JSON format" do
    let(:logger) { Whoosh::Logger.new(output: output, format: :json, level: :debug) }

    it "logs info messages as JSON" do
      logger.info("test_event", key: "value")
      output.rewind
      line = output.read
      parsed = JSON.parse(line)
      expect(parsed["level"]).to eq("info")
      expect(parsed["event"]).to eq("test_event")
      expect(parsed["key"]).to eq("value")
      expect(parsed["ts"]).to be_a(String)
    end

    it "respects log level" do
      logger = Whoosh::Logger.new(output: output, format: :json, level: :warn)
      logger.info("ignored")
      logger.warn("shown")
      output.rewind
      lines = output.read.strip.split("\n")
      expect(lines.length).to eq(1)
      expect(JSON.parse(lines.first)["level"]).to eq("warn")
    end

    it "supports debug, info, warn, error levels" do
      logger.debug("d")
      logger.info("i")
      logger.warn("w")
      logger.error("e")
      output.rewind
      lines = output.read.strip.split("\n")
      expect(lines.length).to eq(4)
    end
  end

  describe "text format" do
    let(:logger) { Whoosh::Logger.new(output: output, format: :text, level: :info) }

    it "logs as human-readable text" do
      logger.info("request_complete", method: "GET", path: "/health")
      output.rewind
      line = output.read
      expect(line).to include("INFO")
      expect(line).to include("request_complete")
    end
  end
end
