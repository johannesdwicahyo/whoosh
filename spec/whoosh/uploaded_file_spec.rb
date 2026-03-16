# spec/whoosh/uploaded_file_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "base64"

RSpec.describe Whoosh::UploadedFile do
  let(:tempfile) { t = Tempfile.new("test"); t.write("Hello, World!"); t.rewind; t }
  let(:rack_hash) { { filename: "test.txt", type: "text/plain", tempfile: tempfile } }
  let(:file) { Whoosh::UploadedFile.new(rack_hash, storage: nil) }

  after { tempfile.close! }

  it("returns filename") { expect(file.filename).to eq("test.txt") }
  it("returns content_type") { expect(file.content_type).to eq("text/plain") }
  it("returns size") { expect(file.size).to eq(13) }
  it("reads content") { expect(file.read).to eq("Hello, World!") }
  it("reads multiple times") { file.read; expect(file.read).to eq("Hello, World!") }
  it("returns UTF-8 text") { expect(file.read_text.encoding).to eq(Encoding::UTF_8) }
  it("returns base64") { expect(Base64.strict_decode64(file.to_base64)).to eq("Hello, World!") }

  it "validates types" do
    expect { file.validate!(types: ["application/pdf"]) }.to raise_error(Whoosh::Errors::ValidationError)
  end

  it "validates size" do
    expect { file.validate!(max_size: 5) }.to raise_error(Whoosh::Errors::ValidationError)
  end

  it "validates blank filename" do
    blank = Whoosh::UploadedFile.new({ filename: "", type: "text/plain", tempfile: tempfile }, storage: nil)
    expect { blank.validate!(types: ["text/plain"]) }.to raise_error(Whoosh::Errors::ValidationError)
  end
end
