# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App streaming integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "stream :sse" do
    before do
      application.get "/events" do
        stream :sse do |out|
          out.event("status", { connected: true })
          out << { data: "hello" }
        end
      end
    end

    it "returns SSE content-type headers" do
      get "/events"
      expect(last_response.headers["content-type"]).to eq("text/event-stream")
    end

    it "writes SSE events to response body" do
      get "/events"
      body = last_response.body
      expect(body).to include("event: status")
      expect(body).to include("hello")
    end
  end

  describe "stream_llm" do
    before do
      application.post "/chat" do |req|
        stream_llm do |out|
          out << "Hello"
          out.finish
        end
      end
    end

    it "returns SSE headers" do
      post "/chat"
      expect(last_response.headers["content-type"]).to eq("text/event-stream")
    end

    it "writes OpenAI-compatible chunks" do
      post "/chat"
      body = last_response.body
      data_line = body.lines.find { |l| l.start_with?("data: {") }
      parsed = JSON.parse(data_line.sub("data: ", "").strip)
      expect(parsed["choices"][0]["delta"]["content"]).to eq("Hello")
      expect(body).to include("data: [DONE]")
    end
  end
end
