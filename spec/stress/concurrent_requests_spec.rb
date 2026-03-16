# spec/stress/concurrent_requests_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack"

RSpec.describe "Concurrent request handling" do
  let(:application) do
    app = Whoosh::App.new
    app.get("/health") { { status: "ok" } }
    app.provide(:counter) { 0 }
    app.get("/count") { |req, counter:| { count: counter } }
    app
  end
  let(:rack_app) { application.to_rack }

  it "handles 100 concurrent requests without errors" do
    threads = 100.times.map do
      Thread.new do
        env = Rack::MockRequest.env_for("/health")
        status, _, body = rack_app.call(env)
        { status: status, body: body.first }
      end
    end

    results = threads.map(&:value)
    expect(results.all? { |r| r[:status] == 200 }).to be true
    expect(results.all? { |r| r[:body].include?("ok") }).to be true
  end

  it "handles mixed routes concurrently" do
    threads = 50.times.map do |i|
      Thread.new do
        path = i.even? ? "/health" : "/count"
        env = Rack::MockRequest.env_for(path)
        status, _, _ = rack_app.call(env)
        status
      end
    end

    statuses = threads.map(&:value)
    expect(statuses.all? { |s| s == 200 }).to be true
  end

  it "rate limiter is thread-safe under concurrent access" do
    app = Whoosh::App.new
    app.rate_limit do
      default limit: 1000, period: 60
    end
    app.get("/test") { { ok: true } }
    rack = app.to_rack

    threads = 50.times.map do
      Thread.new do
        env = Rack::MockRequest.env_for("/test")
        status, _, _ = rack.call(env)
        status
      end
    end

    statuses = threads.map(&:value)
    # All should succeed — limit is 1000, we only send 50
    expect(statuses.all? { |s| s == 200 }).to be true
  end
end
