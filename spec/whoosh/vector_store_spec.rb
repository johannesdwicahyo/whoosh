# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::VectorStore::MemoryStore do
  let(:store) { Whoosh::VectorStore::MemoryStore.new }

  describe "#insert and #search" do
    it "stores and retrieves vectors by similarity" do
      store.insert("docs", id: "doc1", vector: [1.0, 0.0, 0.0], metadata: { title: "Ruby" })
      store.insert("docs", id: "doc2", vector: [0.0, 1.0, 0.0], metadata: { title: "Python" })
      store.insert("docs", id: "doc3", vector: [0.9, 0.1, 0.0], metadata: { title: "Crystal" })

      results = store.search("docs", vector: [1.0, 0.0, 0.0], limit: 2)
      expect(results.length).to eq(2)
      expect(results.first[:id]).to eq("doc1")       # exact match
      expect(results.first[:score]).to be_within(0.01).of(1.0)
      expect(results[1][:id]).to eq("doc3")           # most similar
    end

    it "returns empty for unknown collection" do
      expect(store.search("unknown", vector: [1.0])).to eq([])
    end

    it "includes metadata in results" do
      store.insert("docs", id: "doc1", vector: [1.0, 0.0], metadata: { source: "web" })
      results = store.search("docs", vector: [1.0, 0.0])
      expect(results.first[:metadata][:source]).to eq("web")
    end
  end

  describe "#delete" do
    it "removes a vector" do
      store.insert("docs", id: "doc1", vector: [1.0, 0.0])
      store.delete("docs", id: "doc1")
      expect(store.count("docs")).to eq(0)
    end
  end

  describe "#count" do
    it "returns vector count" do
      store.insert("docs", id: "doc1", vector: [1.0])
      store.insert("docs", id: "doc2", vector: [0.0])
      expect(store.count("docs")).to eq(2)
    end

    it "returns 0 for unknown collection" do
      expect(store.count("unknown")).to eq(0)
    end
  end

  describe "#drop" do
    it "drops entire collection" do
      store.insert("docs", id: "doc1", vector: [1.0])
      store.drop("docs")
      expect(store.count("docs")).to eq(0)
    end
  end
end

RSpec.describe Whoosh::VectorStore do
  describe ".build" do
    it "builds memory store by default" do
      store = Whoosh::VectorStore.build({})
      expect(store).to be_a(Whoosh::VectorStore::MemoryStore)
    end

    it "builds memory store when explicitly configured" do
      store = Whoosh::VectorStore.build({ "vector" => { "adapter" => "memory" } })
      expect(store).to be_a(Whoosh::VectorStore::MemoryStore)
    end
  end
end
