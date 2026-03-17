# spec/whoosh/paginate_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Paginate do
  let(:items) { (1..50).map { |i| { id: i, name: "item-#{i}" } } }

  describe ".offset" do
    it "returns first page" do
      result = Whoosh::Paginate.offset(items, page: 1, per_page: 10)
      expect(result[:data].size).to eq(10)
      expect(result[:data].first[:id]).to eq(1)
      expect(result[:pagination][:total]).to eq(50)
      expect(result[:pagination][:total_pages]).to eq(5)
    end

    it "returns second page" do
      result = Whoosh::Paginate.offset(items, page: 2, per_page: 10)
      expect(result[:data].first[:id]).to eq(11)
    end

    it "returns empty for beyond-range page" do
      result = Whoosh::Paginate.offset(items, page: 100, per_page: 10)
      expect(result[:data]).to be_empty
    end

    it "handles page 0 as page 1" do
      result = Whoosh::Paginate.offset(items, page: 0, per_page: 10)
      expect(result[:pagination][:page]).to eq(1)
    end
  end

  describe ".cursor" do
    it "returns first page without cursor" do
      result = Whoosh::Paginate.cursor(items, limit: 10, column: :id)
      expect(result[:data].size).to eq(10)
      expect(result[:pagination][:has_more]).to be true
      expect(result[:pagination][:next_cursor]).not_to be_nil
    end

    it "returns next page with cursor" do
      first = Whoosh::Paginate.cursor(items, limit: 10, column: :id)
      second = Whoosh::Paginate.cursor(items, cursor: first[:pagination][:next_cursor], limit: 10, column: :id)
      expect(second[:data].first[:id]).to eq(11)
    end

    it "returns has_more false on last page" do
      result = Whoosh::Paginate.cursor(items, limit: 50, column: :id)
      expect(result[:pagination][:has_more]).to be false
      expect(result[:pagination][:next_cursor]).to be_nil
    end
  end
end
