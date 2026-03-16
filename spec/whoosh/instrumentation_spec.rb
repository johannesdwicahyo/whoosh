# spec/whoosh/instrumentation_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Instrumentation do
  let(:bus) { Whoosh::Instrumentation.new }

  describe "#on and #emit" do
    it "subscribes and emits events" do
      events = []
      bus.on(:error) { |data| events << data }
      bus.emit(:error, { message: "boom" })
      expect(events.first[:message]).to eq("boom")
    end

    it "supports multiple subscribers" do
      count = 0
      bus.on(:request) { count += 1 }
      bus.on(:request) { count += 1 }
      bus.emit(:request, {})
      expect(count).to eq(2)
    end

    it "ignores unsubscribed events" do
      expect { bus.emit(:unknown, {}) }.not_to raise_error
    end

    it "continues if subscriber raises" do
      called = false
      bus.on(:error) { raise "crash" }
      bus.on(:error) { called = true }
      bus.emit(:error, {})
      expect(called).to be true
    end
  end
end
