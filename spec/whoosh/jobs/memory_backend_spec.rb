# spec/whoosh/jobs/memory_backend_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Jobs::MemoryBackend do
  let(:backend) { Whoosh::Jobs::MemoryBackend.new }

  describe "#push and #pop" do
    it "queues and dequeues" do
      backend.push({ id: "j1", class_name: "X", args: {} })
      job = backend.pop(timeout: 1)
      expect(job[:id]).to eq("j1")
    end

    it "returns nil on timeout" do
      expect(backend.pop(timeout: 0.1)).to be_nil
    end
  end

  describe "#save and #find" do
    it "stores and retrieves" do
      backend.save({ id: "j1", status: :pending })
      expect(backend.find("j1")[:status]).to eq(:pending)
    end

    it "returns nil for unknown" do
      expect(backend.find("x")).to be_nil
    end

    it "updates records" do
      backend.save({ id: "j1", status: :pending })
      backend.save({ id: "j1", status: :running })
      expect(backend.find("j1")[:status]).to eq(:running)
    end
  end

  describe "#size" do
    it "returns queue size" do
      backend.push({ id: "1" })
      backend.push({ id: "2" })
      expect(backend.size).to eq(2)
    end
  end
end
