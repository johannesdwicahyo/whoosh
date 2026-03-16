# spec/whoosh/cache/redis_store_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Cache::RedisStore do
  describe ".new" do
    it "raises DependencyError if redis gem not available" do
      original = Whoosh::Cache::RedisStore.instance_variable_get(:@redis_available)
      Whoosh::Cache::RedisStore.instance_variable_set(:@redis_available, false)
      expect { Whoosh::Cache::RedisStore.new(url: "redis://localhost") }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Cache::RedisStore.instance_variable_set(:@redis_available, original)
    end
  end

  describe "interface" do
    it "has all cache interface methods" do
      methods = Whoosh::Cache::RedisStore.instance_methods(false)
      expect(methods).to include(:get, :set, :fetch, :delete, :clear, :close)
    end
  end
end
