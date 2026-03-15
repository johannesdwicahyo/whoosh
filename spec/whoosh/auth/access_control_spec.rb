# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::AccessControl do
  let(:acl) { Whoosh::Auth::AccessControl.new }

  before do
    acl.role(:basic, models: ["claude-haiku"])
    acl.role(:standard, models: ["claude-haiku", "claude-sonnet"])
    acl.role(:premium, models: ["claude-haiku", "claude-sonnet", "claude-opus"])
  end

  describe "#check!" do
    it "allows access to permitted models" do
      expect { acl.check!(:standard, "claude-sonnet") }.not_to raise_error
    end

    it "denies access to unpermitted models" do
      expect { acl.check!(:basic, "claude-opus") }.to raise_error(Whoosh::Errors::ForbiddenError)
    end

    it "allows all models for premium role" do
      expect { acl.check!(:premium, "claude-opus") }.not_to raise_error
    end
  end

  describe "#models_for" do
    it "returns allowed models for a role" do
      expect(acl.models_for(:standard)).to eq(["claude-haiku", "claude-sonnet"])
    end

    it "returns empty array for unknown role" do
      expect(acl.models_for(:unknown)).to eq([])
    end
  end
end
