# lib/whoosh/uploaded_file.rb
# frozen_string_literal: true

require "base64"

module Whoosh
  class UploadedFile
    attr_reader :filename, :content_type

    def initialize(rack_hash, storage: nil)
      @filename = rack_hash[:filename]
      @content_type = rack_hash[:type]
      @tempfile = rack_hash[:tempfile]
      @storage = storage
    end

    def size
      @tempfile.size
    end

    def read
      @tempfile.rewind
      @tempfile.read
    end

    def read_text
      read.force_encoding("UTF-8")
    end

    def to_base64
      Base64.strict_encode64(read)
    end

    def save(prefix = "")
      raise Errors::DependencyError, "No storage adapter configured" unless @storage
      @storage.save(self, prefix)
    end

    def validate!(types: nil, max_size: nil)
      errors = []
      errors << { field: "file", message: "No file uploaded" } if @filename.nil? || @filename.empty?
      errors << { field: "file", message: "File type #{@content_type} not allowed" } if types && !types.include?(@content_type)
      errors << { field: "file", message: "File too large (#{size} bytes > #{max_size})" } if max_size && size > max_size
      raise Errors::ValidationError.new(errors) unless errors.empty?
    end
  end
end
