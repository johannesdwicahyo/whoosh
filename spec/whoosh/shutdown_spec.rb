# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Shutdown do
  describe "#register and #execute!" do
    it "executes hooks" do
      shutdown = Whoosh::Shutdown.new
      called = false
      shutdown.register { called = true }
      shutdown.execute!
      expect(called).to be true
    end

    it "executes in reverse order" do
      shutdown = Whoosh::Shutdown.new
      order = []
      shutdown.register { order << :first }
      shutdown.register { order << :second }
      shutdown.execute!
      expect(order).to eq([:second, :first])
    end

    it "continues if a hook raises" do
      output = StringIO.new
      logger = Whoosh::Logger.new(output: output, format: :json, level: :info)
      shutdown = Whoosh::Shutdown.new(logger: logger)
      called = false
      shutdown.register { raise "boom" }
      shutdown.register { called = true }
      shutdown.execute!
      expect(called).to be true
    end

    it "only executes once" do
      shutdown = Whoosh::Shutdown.new
      count = 0
      shutdown.register { count += 1 }
      shutdown.execute!
      shutdown.execute!
      expect(count).to eq(1)
    end
  end
end
