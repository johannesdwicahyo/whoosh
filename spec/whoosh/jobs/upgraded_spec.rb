# frozen_string_literal: true

require "spec_helper"

class ScheduledTestJob < Whoosh::Job
  def perform(value:)
    { result: value }
  end
end

class QueuedTestJob < Whoosh::Job
  queue :critical

  def perform(value:)
    { result: value }
  end
end

class RetryConfigJob < Whoosh::Job
  retry_limit 2
  retry_backoff :exponential

  def perform(msg:)
    raise msg
  end
end

RSpec.describe "Jobs upgrade — scheduling" do
  let(:backend) { Whoosh::Jobs::MemoryBackend.new }

  before { Whoosh::Jobs.configure(backend: backend) }
  after { Whoosh::Jobs.reset! }

  describe "perform_in" do
    it "schedules a job for future execution" do
      job_id = ScheduledTestJob.perform_in(10, value: 42)
      record = Whoosh::Jobs.find(job_id)
      expect(record[:status]).to eq(:scheduled)
      expect(record[:run_at]).to be > Time.now.to_f
    end

    it "is not immediately popped" do
      ScheduledTestJob.perform_in(10, value: 42)
      expect(backend.pop(timeout: 0.1)).to be_nil
    end
  end

  describe "perform_at" do
    it "schedules at a specific time" do
      future = Time.now + 60
      job_id = ScheduledTestJob.perform_at(future, value: 99)
      record = Whoosh::Jobs.find(job_id)
      expect(record[:run_at]).to be_within(1).of(future.to_f)
    end
  end

  describe "scheduled promotion" do
    it "promotes past-due scheduled jobs to the queue" do
      # Schedule for 0.05 seconds from now
      ScheduledTestJob.perform_in(0.05, value: 1)
      expect(backend.pop(timeout: 0.01)).to be_nil  # not ready yet

      sleep 0.06
      job = backend.pop(timeout: 0.1)
      expect(job).not_to be_nil
      expect(job[:id]).to be_a(String)
    end
  end
end

RSpec.describe "Jobs upgrade — named queues" do
  let(:backend) { Whoosh::Jobs::MemoryBackend.new }

  before { Whoosh::Jobs.configure(backend: backend) }
  after { Whoosh::Jobs.reset! }

  it "stores queue name from job class" do
    job_id = QueuedTestJob.perform_async(value: 1)
    record = Whoosh::Jobs.find(job_id)
    expect(record[:queue]).to eq("critical")
  end

  it "defaults to 'default' queue" do
    job_id = ScheduledTestJob.perform_async(value: 1)
    record = Whoosh::Jobs.find(job_id)
    expect(record[:queue]).to eq("default")
  end
end

RSpec.describe "Jobs upgrade — non-blocking retry" do
  let(:backend) { Whoosh::Jobs::MemoryBackend.new }

  before { Whoosh::Jobs.configure(backend: backend) }
  after { Whoosh::Jobs.reset! }

  it "re-enqueues with delay instead of sleeping" do
    job_id = RetryConfigJob.perform_async(msg: "fail")
    worker = Whoosh::Jobs::Worker.new(backend: backend, max_retries: 2, retry_delay: 5)

    # Execute once — should fail and re-enqueue
    worker.run_once(timeout: 1)

    record = backend.find(job_id)
    expect(record[:status]).to eq(:scheduled)
    expect(record[:run_at]).to be > Time.now.to_f
    expect(record[:retry_count]).to eq(1)
  end

  it "uses exponential backoff from job class" do
    expect(RetryConfigJob.retry_backoff).to eq(:exponential)
    expect(RetryConfigJob.retry_limit).to eq(2)
  end
end

RSpec.describe "Jobs upgrade — auto-detect backend" do
  it "builds memory backend when no REDIS_URL" do
    backend = Whoosh::Jobs.build_backend({})
    expect(backend).to be_a(Whoosh::Jobs::MemoryBackend)
  end

  it "builds memory backend when explicitly configured" do
    backend = Whoosh::Jobs.build_backend({ "jobs" => { "backend" => "memory" } })
    expect(backend).to be_a(Whoosh::Jobs::MemoryBackend)
  end
end

RSpec.describe "Jobs upgrade — Redis backend interface" do
  it "raises DependencyError if redis gem not available" do
    original = Whoosh::Jobs::RedisBackend.instance_variable_get(:@redis_available)
    Whoosh::Jobs::RedisBackend.instance_variable_set(:@redis_available, false)
    expect { Whoosh::Jobs::RedisBackend.new(url: "redis://localhost") }.to raise_error(Whoosh::Errors::DependencyError)
    Whoosh::Jobs::RedisBackend.instance_variable_set(:@redis_available, original)
  end

  it "has required interface methods" do
    methods = Whoosh::Jobs::RedisBackend.instance_methods(false)
    expect(methods).to include(:push, :pop, :save, :find, :size, :shutdown)
  end
end
