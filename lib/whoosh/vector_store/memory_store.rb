# frozen_string_literal: true

module Whoosh
  module VectorStore
    class MemoryStore
      def initialize
        @collections = {}
        @mutex = Mutex.new
      end

      # Store a vector with metadata
      def insert(collection, id:, vector:, metadata: {})
        @mutex.synchronize do
          @collections[collection] ||= {}
          @collections[collection][id] = { vector: vector, metadata: metadata }
        end
      end

      # Search by cosine similarity, return top-k results
      def search(collection, vector:, limit: 10)
        @mutex.synchronize do
          items = @collections[collection]
          return [] unless items && !items.empty?

          scored = items.map do |id, data|
            score = cosine_similarity(vector, data[:vector])
            { id: id, score: score, metadata: data[:metadata] }
          end

          scored.sort_by { |r| -r[:score] }.first(limit)
        end
      end

      # Delete a vector
      def delete(collection, id:)
        @mutex.synchronize do
          @collections[collection]&.delete(id)
        end
      end

      # Count vectors in a collection
      def count(collection)
        @mutex.synchronize do
          @collections[collection]&.size || 0
        end
      end

      # Drop a collection
      def drop(collection)
        @mutex.synchronize do
          @collections.delete(collection)
        end
      end

      def close
        # No-op
      end

      private

      def cosine_similarity(a, b)
        return 0.0 if a.empty? || b.empty? || a.length != b.length

        dot = 0.0
        mag_a = 0.0
        mag_b = 0.0

        a.length.times do |i|
          dot += a[i] * b[i]
          mag_a += a[i] * a[i]
          mag_b += b[i] * b[i]
        end

        denom = Math.sqrt(mag_a) * Math.sqrt(mag_b)
        denom.zero? ? 0.0 : dot / denom
      end
    end
  end
end
