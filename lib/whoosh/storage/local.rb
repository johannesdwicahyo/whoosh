# lib/whoosh/storage/local.rb
# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Whoosh
  module Storage
    class Local
      def initialize(root:)
        @root = root
      end

      def save(uploaded_file, prefix = "")
        dir = prefix.empty? ? @root : File.join(@root, prefix)
        FileUtils.mkdir_p(dir)
        filename = "#{SecureRandom.uuid}_#{uploaded_file.filename}"
        path = File.join(dir, filename)
        File.open(path, "wb") { |f| f.write(uploaded_file.read) }
        prefix.empty? ? filename : File.join(prefix, filename)
      end
    end
  end
end
