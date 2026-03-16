# spec/whoosh/app_upload_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App file upload" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before do
    application.post "/upload" do |req|
      file = req.files["file"]
      if file
        { filename: file.filename, size: file.size, content: file.read_text }
      else
        { files: 0 }
      end
    end
  end

  it "handles multipart file upload" do
    # Create a temp file to upload
    tempfile = Tempfile.new("upload_test")
    tempfile.write("test content")
    tempfile.rewind

    post "/upload", "file" => Rack::Test::UploadedFile.new(tempfile.path, "text/plain", false, original_filename: "test.txt")
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["filename"]).to eq("test.txt")
    expect(body["content"]).to eq("test content")

    tempfile.close!
  end

  it "returns empty when no file" do
    post "/upload", {}.to_json, "CONTENT_TYPE" => "application/json"
    expect(last_response.status).to eq(200)
  end
end
