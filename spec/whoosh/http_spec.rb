# spec/whoosh/http_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "webrick"

RSpec.describe Whoosh::HTTP do
  before(:all) do
    @server = WEBrick::HTTPServer.new(Port: 9977, Logger: WEBrick::Log.new("/dev/null"), AccessLog: [])
    @server.mount_proc("/echo") do |req, res|
      res.content_type = "application/json"
      body = req.body || ""
      res.body = JSON.generate({
        method: req.request_method,
        body: body.empty? ? nil : (JSON.parse(body) rescue body),
        headers: { "x-custom" => req["X-Custom"] }
      })
    end
    @server.mount_proc("/status") do |req, res|
      code = req.query["code"]&.to_i || 200
      res.status = code
      res.content_type = "application/json"
      res.body = JSON.generate({ status: code })
    end
    Thread.new { @server.start }
    sleep 0.5
  end

  after(:all) { @server.shutdown }

  describe ".get" do
    it "makes a GET request" do
      response = Whoosh::HTTP.get("http://localhost:9977/echo")
      expect(response.ok?).to be true
      expect(response.json["method"]).to eq("GET")
    end

    it "sends custom headers" do
      response = Whoosh::HTTP.get("http://localhost:9977/echo", headers: { "X-Custom" => "test" })
      expect(response.json["headers"]["x-custom"]).to eq("test")
    end
  end

  describe ".post" do
    it "sends JSON body" do
      response = Whoosh::HTTP.post("http://localhost:9977/echo", json: { message: "hello" })
      expect(response.ok?).to be true
      expect(response.json["body"]["message"]).to eq("hello")
    end
  end

  describe "response" do
    it "reports non-2xx status" do
      response = Whoosh::HTTP.get("http://localhost:9977/status?code=404")
      expect(response.status).to eq(404)
      expect(response.ok?).to be false
    end

    it "parses JSON" do
      expect(Whoosh::HTTP.get("http://localhost:9977/echo").json).to be_a(Hash)
    end

    it "returns raw body" do
      expect(Whoosh::HTTP.get("http://localhost:9977/echo").body).to be_a(String)
    end
  end

  describe "error handling" do
    it "raises ConnectionError for refused connection" do
      expect { Whoosh::HTTP.get("http://localhost:19999/nope") }.to raise_error(Whoosh::HTTP::ConnectionError)
    end
  end
end
