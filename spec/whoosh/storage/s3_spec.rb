# spec/whoosh/storage/s3_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Storage::S3 do
  it "raises DependencyError if aws-sdk-s3 not available" do
    original = Whoosh::Storage::S3.instance_variable_get(:@aws_available)
    Whoosh::Storage::S3.instance_variable_set(:@aws_available, false)
    expect { Whoosh::Storage::S3.new(bucket: "test") }.to raise_error(Whoosh::Errors::DependencyError)
    Whoosh::Storage::S3.instance_variable_set(:@aws_available, original)
  end
end
