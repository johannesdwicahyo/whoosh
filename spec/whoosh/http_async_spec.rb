# spec/whoosh/http_async_spec.rb
# frozen_string_literal: true
require "spec_helper"
require "webrick"

RSpec.describe "Async HTTP" do
  before(:all) do
    @server = WEBrick::HTTPServer.new(Port: 9978, Logger: WEBrick::Log.new("/dev/null"), AccessLog: [])
    @server.mount_proc("/data") { |req, res| res.body = '{"ok":true}'; res.content_type = "application/json" }
    Thread.new { @server.start }
    sleep 0.5
  end
  after(:all) { @server.shutdown }

  describe ".concurrent" do
    it "runs multiple requests in parallel" do
      results = Whoosh::HTTP.concurrent(
        { method: :get, url: "http://localhost:9978/data" },
        { method: :get, url: "http://localhost:9978/data" }
      )
      expect(results.length).to eq(2)
      expect(results.all?(&:ok?)).to be true
    end
  end

  describe ".async" do
    it "returns a thread (future)" do
      future = Whoosh::HTTP.async.get("http://localhost:9978/data")
      expect(future).to be_a(Thread)
      response = future.value
      expect(response.ok?).to be true
    end
  end
end
