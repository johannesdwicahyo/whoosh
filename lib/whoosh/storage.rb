# lib/whoosh/storage.rb
# frozen_string_literal: true

module Whoosh
  module Storage
    autoload :Local, "whoosh/storage/local"
    autoload :S3,    "whoosh/storage/s3"

    def self.build(config_data = {})
      config = config_data["storage"] || {}
      adapter = config["adapter"] || "local"
      case adapter
      when "local" then Local.new(root: config["local_root"] || "uploads")
      when "s3" then S3.new(bucket: config["s3_bucket"], region: config["s3_region"] || "us-east-1",
        access_key_id: config["s3_access_key_id"], secret_access_key: config["s3_secret_access_key"])
      else raise ArgumentError, "Unknown storage adapter: #{adapter}"
      end
    end
  end
end
