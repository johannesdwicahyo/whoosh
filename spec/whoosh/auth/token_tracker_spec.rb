# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::TokenTracker do
  let(:tracker) { Whoosh::Auth::TokenTracker.new }

  describe "#record" do
    it "records token usage" do
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 120 })
      usage = tracker.usage_for("sk-1")
      expect(usage[:total_tokens]).to eq(170)
    end

    it "accumulates usage across calls" do
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 30, completion: 60 })
      expect(tracker.usage_for("sk-1")[:total_tokens]).to eq(240)
    end
  end

  describe "#on_usage" do
    it "calls the callback on each record" do
      events = []
      tracker.on_usage { |key, endpoint, tokens| events << { key: key, endpoint: endpoint, tokens: tokens } }
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      expect(events.length).to eq(1)
      expect(events.first[:key]).to eq("sk-1")
    end
  end

  describe "#usage_for" do
    it "returns zero for unknown keys" do
      expect(tracker.usage_for("unknown")[:total_tokens]).to eq(0)
    end

    it "includes per-endpoint breakdown" do
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      tracker.record(key: "sk-1", endpoint: "/embed", tokens: { prompt: 200, completion: 0 })
      usage = tracker.usage_for("sk-1")
      expect(usage[:endpoints]["/chat"]).to eq(150)
      expect(usage[:endpoints]["/embed"]).to eq(200)
    end
  end

  describe "#reset" do
    it "clears usage for a key" do
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      tracker.reset("sk-1")
      expect(tracker.usage_for("sk-1")[:total_tokens]).to eq(0)
    end
  end
end
