# spec/whoosh/cache/memory_store_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Cache::MemoryStore do
  let(:store) { Whoosh::Cache::MemoryStore.new(default_ttl: 300) }

  describe "#set and #get" do
    it "stores and retrieves values" do
      store.set("key", { name: "test" })
      expect(store.get("key")).to eq({ "name" => "test" })
    end

    it "returns nil for missing keys" do
      expect(store.get("missing")).to be_nil
    end

    it "returns nil for expired keys" do
      store.set("key", "value", ttl: 0.01)
      sleep 0.02
      expect(store.get("key")).to be_nil
    end
  end

  describe "#fetch" do
    it "returns cached value on hit" do
      store.set("key", "cached")
      result = store.fetch("key") { "computed" }
      expect(result).to eq("cached")
    end

    it "computes and stores on miss" do
      result = store.fetch("key", ttl: 60) { "computed" }
      expect(result).to eq("computed")
      expect(store.get("key")).to eq("computed")
    end
  end

  describe "#delete" do
    it "removes a key" do
      store.set("key", "value")
      store.delete("key")
      expect(store.get("key")).to be_nil
    end
  end

  describe "#clear" do
    it "removes all keys" do
      store.set("a", 1)
      store.set("b", 2)
      store.clear
      expect(store.get("a")).to be_nil
    end
  end

  describe "#close" do
    it "is a no-op" do
      expect { store.close }.not_to raise_error
    end
  end
end
