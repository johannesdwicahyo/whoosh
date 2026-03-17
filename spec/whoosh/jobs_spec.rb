# spec/whoosh/jobs_spec.rb
# frozen_string_literal: true

require "spec_helper"

class TestGreetJob < Whoosh::Job
  def perform(name:)
    { greeting: "Hello, #{name}!" }
  end
end

class TestDIJob < Whoosh::Job
  inject :greeting_service
  def perform(name:)
    { message: greeting_service.greet(name) }
  end
end

RSpec.describe Whoosh::Jobs do
  before { Whoosh::Jobs.configure(backend: Whoosh::Jobs::MemoryBackend.new) }
  after { Whoosh::Jobs.reset! }

  describe ".enqueue" do
    it "returns job_id" do
      job_id = Whoosh::Jobs.enqueue(TestGreetJob, name: "Alice")
      expect(job_id).to match(/\A[a-f0-9-]+\z/)
    end

    it "creates pending record" do
      job_id = Whoosh::Jobs.enqueue(TestGreetJob, name: "Alice")
      expect(Whoosh::Jobs.find(job_id)[:status]).to eq(:pending)
    end
  end

  describe ".find" do
    it "returns nil for unknown" do
      expect(Whoosh::Jobs.find("x")).to be_nil
    end
  end

  describe "perform_async" do
    it "delegates to enqueue" do
      job_id = TestGreetJob.perform_async(name: "Bob")
      expect(Whoosh::Jobs.find(job_id)).not_to be_nil
    end
  end

  describe "unconfigured" do
    it "raises" do
      Whoosh::Jobs.reset!
      expect { TestGreetJob.perform_async(name: "X") }.to raise_error(Whoosh::Errors::DependencyError)
    end
  end
end

RSpec.describe Whoosh::Job do
  it("stores deps") { expect(TestDIJob.dependencies).to eq([:greeting_service]) }
  it("empty by default") { expect(TestGreetJob.dependencies).to eq([]) }
end
