# spec/whoosh/jobs/worker_spec.rb
# frozen_string_literal: true

require "spec_helper"

class WorkerTestJob < Whoosh::Job
  def perform(value:)
    { doubled: value * 2 }
  end
end

class WorkerFailJob < Whoosh::Job
  def perform(msg:)
    raise msg
  end
end

RSpec.describe Whoosh::Jobs::Worker do
  let(:backend) { Whoosh::Jobs::MemoryBackend.new }

  before { Whoosh::Jobs.configure(backend: backend) }
  after { Whoosh::Jobs.reset! }

  describe "#run_once" do
    it "executes job and sets completed" do
      job_id = WorkerTestJob.perform_async(value: 21)
      worker = Whoosh::Jobs::Worker.new(backend: backend, max_retries: 3, retry_delay: 0)
      worker.run_once(timeout: 1)

      record = backend.find(job_id)
      expect(record[:status]).to eq(:completed)
      expect(record[:result]).to eq({ "doubled" => 42 })
    end

    it "fails after max retries" do
      job_id = WorkerFailJob.perform_async(msg: "boom")
      worker = Whoosh::Jobs::Worker.new(backend: backend, max_retries: 1, retry_delay: 0)
      2.times { worker.run_once(timeout: 1) }

      record = backend.find(job_id)
      expect(record[:status]).to eq(:failed)
      expect(record[:error][:message]).to eq("boom")
    end
  end

  describe "DI injection" do
    it "injects dependencies" do
      svc = Object.new
      svc.define_singleton_method(:greet) { |n| "Hi #{n}" }

      di = Whoosh::DependencyInjection.new
      di.provide(:svc) { svc }
      Whoosh::Jobs.configure(backend: backend, di: di)

      job_class = Class.new(Whoosh::Job) {
        inject :svc
        define_method(:perform) { |name:| { msg: svc.greet(name) } }
      }
      # Need a name for const_get
      Object.const_set(:WorkerDITestJob, job_class) unless defined?(WorkerDITestJob)

      job_id = WorkerDITestJob.perform_async(name: "Alice")
      worker = Whoosh::Jobs::Worker.new(backend: backend, di: di, max_retries: 0, retry_delay: 0)
      worker.run_once(timeout: 1)

      record = backend.find(job_id)
      expect(record[:status]).to eq(:completed)
      expect(record[:result]["msg"]).to eq("Hi Alice")
    end
  end
end
