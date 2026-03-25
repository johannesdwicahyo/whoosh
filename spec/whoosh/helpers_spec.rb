# spec/whoosh/helpers_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "tmpdir"

RSpec.describe "Response helpers" do
  include Rack::Test::Methods
  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "redirect" do
    before { application.get("/old") { redirect("/new") } }
    it "returns 302 with location" do
      get "/old"
      expect(last_response.status).to eq(302)
      expect(last_response.headers["location"]).to eq("/new")
    end
  end

  describe "redirect with 301" do
    before { application.get("/moved") { redirect("/permanent", status: 301) } }
    it "returns 301" do
      get "/moved"
      expect(last_response.status).to eq(301)
    end
  end

  describe "cookies" do
    before do
      application.get("/cookie") do |req|
        { token: req.cookies["session"] }
      end
    end
    it "reads cookies" do
      get "/cookie", {}, { "HTTP_COOKIE" => "session=abc123" }
      expect(JSON.parse(last_response.body)["token"]).to eq("abc123")
    end
  end

  describe "download" do
    before { application.get("/dl") { download("csv,data", filename: "report.csv") } }
    it "returns attachment" do
      get "/dl"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-disposition"]).to include("report.csv")
      expect(last_response.body).to eq("csv,data")
    end
  end

  describe "Response.file" do
    it "serves a file" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.txt"), "hello")
        status, headers, body = Whoosh::Response.file(File.join(dir, "test.txt"))
        expect(status).to eq(200)
        expect(headers["content-type"]).to eq("text/plain")
        expect(body.first).to eq("hello")
      end
    end

    it "raises 404 for missing" do
      expect { Whoosh::Response.file("/nonexistent") }.to raise_error(Whoosh::Errors::NotFoundError)
    end

    it "guesses content type" do
      expect(Whoosh::Response.guess_content_type("file.json")).to eq("application/json")
      expect(Whoosh::Response.guess_content_type("img.png")).to eq("image/png")
      expect(Whoosh::Response.guess_content_type("unknown.xyz")).to eq("application/octet-stream")
    end
  end
end
