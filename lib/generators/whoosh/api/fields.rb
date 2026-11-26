module Whoosh
  module Generators
    # Turns database columns into schema field lines. Plain Ruby, so it can be tested without Rails.
    module Fields
      TYPES = { integer: :integer, bigint: :integer, string: :string, text: :text, decimal: :decimal, float: :float,
                boolean: :boolean, date: :date, datetime: :datetime, timestamp: :datetime, timestamptz: :datetime,
                time: :time, uuid: :uuid, json: :json, jsonb: :json }.freeze
      # An output schema is a promise to publish, so anything that smells like a credential is left out.
      SENSITIVE = /password|digest|secret|token|salt|otp|encrypted|api_key|ssn/i

      # columns respond to name, type and scale; enums are names of Rails enum columns, which read as strings.
      # Returns [field lines, names left out].
      def self.from(columns, enums: [])
        skipped = []
        lines = columns.filter_map do |column|
          type = enums.include?(column.name) ? :string : TYPES[column.type&.to_sym]
          if type.nil? || column.name.match?(SENSITIVE)
            skipped << column.name
            next
          end
          scale = type == :decimal && column.scale ? ", scale: #{column.scale}" : ""
          "field :#{column.name}, :#{type}#{scale}"
        end
        [lines, skipped]
      end
    end
  end
end
