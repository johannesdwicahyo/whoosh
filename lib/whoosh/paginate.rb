# lib/whoosh/paginate.rb
# frozen_string_literal: true

require "base64"

module Whoosh
  module Paginate
    def self.offset(collection, page:, per_page:)
      page = [page.to_i, 1].max
      per_page = [per_page.to_i, 1].max

      if collection.is_a?(Array)
        total = collection.size
        data = collection.slice((page - 1) * per_page, per_page) || []
      else
        # Sequel dataset
        total = collection.count
        data = collection.limit(per_page).offset((page - 1) * per_page).all
      end

      total_pages = (total.to_f / per_page).ceil

      {
        data: data,
        pagination: { page: page, per_page: per_page, total: total, total_pages: total_pages }
      }
    end

    def self.cursor(collection, cursor: nil, limit: 20, column: :id)
      limit = [limit.to_i, 1].max
      cursor_value = cursor ? Base64.urlsafe_decode64(cursor) : nil

      if collection.is_a?(Array)
        filtered = if cursor_value
          numeric = cursor_value =~ /\A\d+\z/
          collection.select do |item|
            val = item[column]
            numeric ? val.to_i > cursor_value.to_i : val.to_s > cursor_value
          end
        else
          collection
        end
        items = filtered.first(limit + 1)
      else
        # Sequel dataset
        filtered = cursor_value ? collection.where { |o| o.__send__(column) > cursor_value } : collection
        items = filtered.limit(limit + 1).all
      end

      has_more = items.size > limit
      data = has_more ? items.first(limit) : items

      next_cursor = if has_more && data.last
        val = data.last.is_a?(Hash) ? data.last[column] : data.last.send(column)
        Base64.urlsafe_encode64(val.to_s, padding: false)
      end

      {
        data: data,
        pagination: { next_cursor: next_cursor, has_more: has_more, limit: limit }
      }
    end
  end
end
