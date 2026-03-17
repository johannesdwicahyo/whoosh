# spec/whoosh/metrics_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Metrics do
  let(:metrics) { Whoosh::Metrics.new }

  describe "#increment" do
    it "increments counter" do
      metrics.increment("requests_total", labels: { method: "GET" })
      metrics.increment("requests_total", labels: { method: "GET" })
      output = metrics.to_prometheus
      expect(output).to include('requests_total{method="GET"} 2')
    end
  end

  describe "#gauge" do
    it "sets gauge value" do
      metrics.gauge("active_streams", 5)
      expect(metrics.to_prometheus).to include("active_streams 5")
    end
  end

  describe "#observe" do
    it "tracks sum and count" do
      metrics.observe("duration_seconds", 0.1, labels: { path: "/health" })
      metrics.observe("duration_seconds", 0.2, labels: { path: "/health" })
      output = metrics.to_prometheus
      expect(output).to include("duration_seconds_sum")
      expect(output).to include("duration_seconds_count")
    end
  end

  describe "#to_prometheus" do
    it "outputs valid Prometheus text format" do
      metrics.increment("http_total", labels: { status: "200" })
      output = metrics.to_prometheus
      expect(output).to include("# TYPE http_total counter")
      expect(output).to include('http_total{status="200"} 1')
    end
  end
end
