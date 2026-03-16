# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe "Request-scoped logger" do
  describe "Logger#with_context" do
    it "includes context fields in log output" do
      output = StringIO.new
      logger = Whoosh::Logger.new(output: output, format: :json, level: :info)
      scoped = logger.with_context(request_id: "abc-123")
      scoped.info("test_event", key: "value")
      output.rewind
      parsed = JSON.parse(output.read)
      expect(parsed["request_id"]).to eq("abc-123")
      expect(parsed["event"]).to eq("test_event")
    end

    it "does not pollute original logger" do
      output = StringIO.new
      logger = Whoosh::Logger.new(output: output, format: :json, level: :info)
      logger.with_context(request_id: "abc")
      logger.info("original")
      output.rewind
      parsed = JSON.parse(output.read)
      expect(parsed).not_to have_key("request_id")
    end
  end

  describe "Request#logger" do
    it "returns a scoped logger with request_id" do
      output = StringIO.new
      logger = Whoosh::Logger.new(output: output, format: :json, level: :info)
      env = Rack::MockRequest.env_for("/test")
      env["whoosh.request_id"] = "req-456"
      env["whoosh.logger"] = logger
      req = Whoosh::Request.new(env)
      req.logger.info("from_handler")
      output.rewind
      parsed = JSON.parse(output.read)
      expect(parsed["request_id"]).to eq("req-456")
    end
  end
end
