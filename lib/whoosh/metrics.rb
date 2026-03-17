# lib/whoosh/metrics.rb
# frozen_string_literal: true

module Whoosh
  class Metrics
    def initialize
      @counters = {}
      @gauges = {}
      @summaries = {}
      @mutex = Mutex.new
    end

    def increment(name, labels: {}, by: 1)
      key = metric_key(name, labels)
      @mutex.synchronize { @counters[key] = (@counters[key] || 0) + by }
    end

    def gauge(name, value, labels: {})
      key = metric_key(name, labels)
      @mutex.synchronize { @gauges[key] = value }
    end

    def observe(name, value, labels: {})
      key = metric_key(name, labels)
      @mutex.synchronize do
        @summaries[key] ||= { sum: 0.0, count: 0 }
        @summaries[key][:sum] += value
        @summaries[key][:count] += 1
      end
    end

    def to_prometheus
      lines = []

      @mutex.synchronize do
        @counters.each do |key, value|
          name, labels = parse_key(key)
          lines << "# TYPE #{name} counter" unless lines.any? { |l| l.include?("TYPE #{name}") }
          lines << "#{name}#{format_labels(labels)} #{value}"
        end

        @gauges.each do |key, value|
          name, labels = parse_key(key)
          lines << "# TYPE #{name} gauge" unless lines.any? { |l| l.include?("TYPE #{name}") }
          lines << "#{name}#{format_labels(labels)} #{value}"
        end

        @summaries.each do |key, data|
          name, labels = parse_key(key)
          unless lines.any? { |l| l.include?("TYPE #{name}") }
            lines << "# TYPE #{name} summary"
          end
          lines << "#{name}_sum#{format_labels(labels)} #{data[:sum]}"
          lines << "#{name}_count#{format_labels(labels)} #{data[:count]}"
        end
      end

      lines.join("\n") + "\n"
    end

    private

    def metric_key(name, labels)
      "#{name}|#{labels.sort.map { |k, v| "#{k}=#{v}" }.join(",")}"
    end

    def parse_key(key)
      name, label_str = key.split("|", 2)
      labels = {}
      label_str.split(",").each do |pair|
        next if pair.empty?
        k, v = pair.split("=", 2)
        labels[k] = v
      end
      [name, labels]
    end

    def format_labels(labels)
      return "" if labels.empty?
      pairs = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(",")
      "{#{pairs}}"
    end
  end
end
