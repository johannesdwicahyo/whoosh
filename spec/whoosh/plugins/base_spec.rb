# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Plugins::Base do
  describe "hook interface" do
    it "does not act as middleware by default" do
      expect(Whoosh::Plugins::Base.middleware?).to be false
    end

    it "can be subclassed with middleware hooks" do
      plugin = Class.new(Whoosh::Plugins::Base) do
        def self.middleware? = true

        def self.before_request(req, config)
          { checked: true }
        end

        def self.after_response(res, config)
          { verified: true }
        end
      end

      expect(plugin.middleware?).to be true
      expect(plugin.before_request(nil, nil)).to eq({ checked: true })
      expect(plugin.after_response(nil, nil)).to eq({ verified: true })
    end
  end

  describe ".gem_name" do
    it "can declare the gem name" do
      plugin = Class.new(Whoosh::Plugins::Base) do
        gem_name "lingua-ruby"
      end

      expect(plugin.gem_name).to eq("lingua-ruby")
    end
  end

  describe ".accessor_name" do
    it "can declare the accessor name" do
      plugin = Class.new(Whoosh::Plugins::Base) do
        accessor_name :lingua
      end

      expect(plugin.accessor_name).to eq(:lingua)
    end
  end

  describe ".initialize_plugin" do
    it "returns nil by default (subclasses override)" do
      expect(Whoosh::Plugins::Base.initialize_plugin({})).to be_nil
    end
  end
end
