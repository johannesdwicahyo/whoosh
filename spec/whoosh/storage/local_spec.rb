# spec/whoosh/storage/local_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "tempfile"

RSpec.describe Whoosh::Storage::Local do
  it "saves file to disk" do
    Dir.mktmpdir do |dir|
      storage = Whoosh::Storage::Local.new(root: dir)
      tempfile = Tempfile.new("test"); tempfile.write("content"); tempfile.rewind
      file = Whoosh::UploadedFile.new({ filename: "doc.txt", type: "text/plain", tempfile: tempfile }, storage: storage)

      path = file.save("docs")
      expect(path).to match(%r{docs/.+_doc\.txt})
      expect(File.read(File.join(dir, path))).to eq("content")
      tempfile.close!
    end
  end
end
