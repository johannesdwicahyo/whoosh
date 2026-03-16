# lib/whoosh/storage/s3.rb
# frozen_string_literal: true

require "securerandom"

module Whoosh
  module Storage
    class S3
      @aws_available = nil

      def self.available?
        if @aws_available.nil?
          @aws_available = begin; require "aws-sdk-s3"; true; rescue LoadError; false; end
        end
        @aws_available
      end

      def initialize(bucket:, region: "us-east-1", access_key_id: nil, secret_access_key: nil)
        raise Errors::DependencyError, "S3 storage requires the 'aws-sdk-s3' gem" unless self.class.available?
        @bucket = bucket
        @client = Aws::S3::Client.new(region: region, access_key_id: access_key_id, secret_access_key: secret_access_key)
      end

      def save(uploaded_file, prefix = "")
        key = prefix.empty? ? "#{SecureRandom.uuid}_#{uploaded_file.filename}" : "#{prefix}/#{SecureRandom.uuid}_#{uploaded_file.filename}"
        @client.put_object(bucket: @bucket, key: key, body: uploaded_file.read)
        key
      end
    end
  end
end
