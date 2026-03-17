# Background Jobs Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add background job system with in-memory queue, worker threads, DI injection into jobs, status tracking, and retry logic.

**Architecture:** `Whoosh::Job` base class with `inject` DSL and `perform_async`. `Whoosh::Jobs` module-level API with `configure/enqueue/find`. `MemoryBackend` with Mutex+ConditionVariable queue. `Worker` thread loop with retry. Scoped to memory backend only — DB and Redis backends deferred.

**Tech Stack:** Ruby 3.4+, RSpec.

**Spec:** `docs/superpowers/specs/2026-03-17-background-jobs-design.md`

**Depends on:** File & HTTP complete (468 tests passing).

---

## Chunk 1: Core Job System

### Task 1: Memory Backend

**Files:**
- Create: `lib/whoosh/jobs/memory_backend.rb`
- Create: `spec/whoosh/jobs/memory_backend_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/jobs/memory_backend_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Jobs::MemoryBackend do
  let(:backend) { Whoosh::Jobs::MemoryBackend.new }

  describe "#push and #pop" do
    it "queues and dequeues jobs" do
      backend.push({ id: "job-1", class_name: "TestJob", args: {} })
      job = backend.pop(timeout: 1)
      expect(job[:id]).to eq("job-1")
    end

    it "returns nil on timeout when empty" do
      job = backend.pop(timeout: 0.1)
      expect(job).to be_nil
    end
  end

  describe "#save and #find" do
    it "stores and retrieves job records" do
      record = { id: "job-1", status: :pending, result: nil, error: nil, retry_count: 0,
                 created_at: Time.now.to_f, started_at: nil, completed_at: nil }
      backend.save(record)
      found = backend.find("job-1")
      expect(found[:status]).to eq(:pending)
    end

    it "returns nil for unknown job" do
      expect(backend.find("unknown")).to be_nil
    end

    it "updates existing records" do
      record = { id: "job-1", status: :pending }
      backend.save(record)
      backend.save(record.merge(status: :running))
      expect(backend.find("job-1")[:status]).to eq(:running)
    end
  end

  describe "#size" do
    it "returns queue size" do
      backend.push({ id: "1" })
      backend.push({ id: "2" })
      expect(backend.size).to eq(2)
    end
  end
end
```

- [ ] **Step 2: Write implementation**

```ruby
# lib/whoosh/jobs/memory_backend.rb
# frozen_string_literal: true

module Whoosh
  module Jobs
    class MemoryBackend
      def initialize
        @queue = []
        @records = {}
        @mutex = Mutex.new
        @cv = ConditionVariable.new
      end

      def push(job_data)
        @mutex.synchronize do
          @queue << job_data
          @cv.signal
        end
      end

      def pop(timeout: 5)
        @mutex.synchronize do
          if @queue.empty?
            @cv.wait(@mutex, timeout)
          end
          @queue.shift
        end
      end

      def save(record)
        @mutex.synchronize do
          @records[record[:id]] = record
        end
      end

      def find(id)
        @mutex.synchronize do
          @records[id]&.dup
        end
      end

      def size
        @mutex.synchronize { @queue.size }
      end

      def shutdown
        @mutex.synchronize { @cv.broadcast }
      end
    end
  end
end
```

- [ ] **Step 3: Run tests, commit**

```bash
git add lib/whoosh/jobs/memory_backend.rb spec/whoosh/jobs/memory_backend_spec.rb
git commit -m "feat: add Jobs::MemoryBackend with thread-safe queue and record store"
```

---

### Task 2: Jobs Module + Job Base Class

**Files:**
- Create: `lib/whoosh/jobs.rb`
- Create: `lib/whoosh/job.rb`
- Create: `spec/whoosh/jobs_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/jobs_spec.rb
# frozen_string_literal: true

require "spec_helper"

# Test job class
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
  before do
    backend = Whoosh::Jobs::MemoryBackend.new
    Whoosh::Jobs.configure(backend: backend)
  end

  after { Whoosh::Jobs.reset! }

  describe ".enqueue" do
    it "queues a job and returns job_id" do
      job_id = Whoosh::Jobs.enqueue(TestGreetJob, name: "Alice")
      expect(job_id).to match(/\A[a-f0-9-]+\z/)
    end

    it "creates a pending job record" do
      job_id = Whoosh::Jobs.enqueue(TestGreetJob, name: "Alice")
      record = Whoosh::Jobs.find(job_id)
      expect(record[:status]).to eq(:pending)
      expect(record[:class_name]).to eq("TestGreetJob")
    end
  end

  describe ".find" do
    it "returns nil for unknown job" do
      expect(Whoosh::Jobs.find("unknown")).to be_nil
    end
  end

  describe "perform_async" do
    it "delegates to Jobs.enqueue" do
      job_id = TestGreetJob.perform_async(name: "Bob")
      expect(Whoosh::Jobs.find(job_id)[:status]).to eq(:pending)
    end
  end

  describe "unconfigured" do
    it "raises when not configured" do
      Whoosh::Jobs.reset!
      expect { TestGreetJob.perform_async(name: "X") }.to raise_error(Whoosh::Errors::DependencyError)
    end
  end
end

RSpec.describe Whoosh::Job do
  describe ".inject" do
    it "stores dependency names" do
      expect(TestDIJob.dependencies).to eq([:greeting_service])
    end
  end

  describe ".dependencies" do
    it "returns empty array by default" do
      expect(TestGreetJob.dependencies).to eq([])
    end
  end
end
```

- [ ] **Step 2: Write implementation**

```ruby
# lib/whoosh/jobs.rb
# frozen_string_literal: true

require "securerandom"

module Whoosh
  module Jobs
    autoload :MemoryBackend, "whoosh/jobs/memory_backend"
    autoload :Worker,        "whoosh/jobs/worker"

    @backend = nil
    @di = nil

    class << self
      attr_reader :backend, :di

      def configure(backend:, di: nil)
        @backend = backend
        @di = di
      end

      def configured?
        !!@backend
      end

      def enqueue(job_class, **args)
        raise Errors::DependencyError, "Jobs not configured — boot a Whoosh::App first" unless configured?

        id = SecureRandom.uuid
        record = {
          id: id,
          class_name: job_class.name,
          args: args,
          status: :pending,
          result: nil,
          error: nil,
          retry_count: 0,
          created_at: Time.now.to_f,
          started_at: nil,
          completed_at: nil
        }
        @backend.save(record)
        @backend.push({ id: id, class_name: job_class.name, args: args })
        id
      end

      def find(id)
        raise Errors::DependencyError, "Jobs not configured" unless configured?
        @backend.find(id)
      end

      def reset!
        @backend = nil
        @di = nil
      end
    end
  end
end
```

```ruby
# lib/whoosh/job.rb
# frozen_string_literal: true

module Whoosh
  class Job
    class << self
      def inject(*names)
        @dependencies = names
      end

      def dependencies
        @dependencies || []
      end

      def perform_async(**args)
        Jobs.enqueue(self, **args)
      end
    end

    def perform(**args)
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end
  end
end
```

- [ ] **Step 3: Add autoloads to lib/whoosh.rb**

Add `autoload :Job, "whoosh/job"` and `autoload :Jobs, "whoosh/jobs"`.

- [ ] **Step 4: Run tests, commit**

```bash
git add lib/whoosh/jobs.rb lib/whoosh/job.rb spec/whoosh/jobs_spec.rb lib/whoosh.rb
git commit -m "feat: add Jobs module and Job base class with inject DSL and perform_async"
```

---

## Chunk 2: Worker + App Integration

### Task 3: Worker

**Files:**
- Create: `lib/whoosh/jobs/worker.rb`
- Create: `spec/whoosh/jobs/worker_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
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
    it "executes a job and sets status to completed" do
      job_id = WorkerTestJob.perform_async(value: 21)
      worker = Whoosh::Jobs::Worker.new(backend: backend, max_retries: 3, retry_delay: 0)
      worker.run_once(timeout: 1)

      record = backend.find(job_id)
      expect(record[:status]).to eq(:completed)
      expect(record[:result]).to eq({ "doubled" => 42 })
    end

    it "sets status to failed after max retries" do
      job_id = WorkerFailJob.perform_async(msg: "boom")
      worker = Whoosh::Jobs::Worker.new(backend: backend, max_retries: 1, retry_delay: 0)

      # First attempt + 1 retry = 2 runs
      2.times { worker.run_once(timeout: 1) }

      record = backend.find(job_id)
      expect(record[:status]).to eq(:failed)
      expect(record[:error][:message]).to eq("boom")
    end
  end

  describe "DI injection" do
    it "injects dependencies into job instance" do
      service = Object.new
      service.define_singleton_method(:greet) { |name| "Hi #{name}" }

      di = Whoosh::DependencyInjection.new
      di.provide(:greeting_service) { service }
      Whoosh::Jobs.configure(backend: backend, di: di)

      # Use TestDIJob from jobs_spec if available, or define inline
      job_class = Class.new(Whoosh::Job) do
        inject :greeting_service
        define_method(:perform) { |name:| { msg: greeting_service.greet(name) } }
      end

      job_id = job_class.perform_async(name: "Alice")
      worker = Whoosh::Jobs::Worker.new(backend: backend, di: di, max_retries: 0, retry_delay: 0)
      worker.run_once(timeout: 1)

      record = backend.find(job_id)
      expect(record[:status]).to eq(:completed)
      expect(record[:result]["msg"]).to eq("Hi Alice")
    end
  end
end
```

- [ ] **Step 2: Write implementation**

```ruby
# lib/whoosh/jobs/worker.rb
# frozen_string_literal: true

module Whoosh
  module Jobs
    class Worker
      def initialize(backend:, di: nil, max_retries: 3, retry_delay: 5, instrumentation: nil)
        @backend = backend
        @di = di
        @max_retries = max_retries
        @retry_delay = retry_delay
        @instrumentation = instrumentation
        @running = true
      end

      def run_once(timeout: 5)
        job_data = @backend.pop(timeout: timeout)
        return unless job_data

        execute(job_data)
      end

      def run_loop
        while @running
          run_once
        end
      end

      def stop
        @running = false
      end

      private

      def execute(job_data)
        id = job_data[:id]
        class_name = job_data[:class_name]
        args = job_data[:args]

        # Update status to running
        record = @backend.find(id) || {}
        record = record.merge(status: :running, started_at: Time.now.to_f)
        @backend.save(record)

        # Resolve job class
        job_class = Object.const_get(class_name)
        job = job_class.new

        # Inject DI dependencies
        if @di && job_class.respond_to?(:dependencies)
          job_class.dependencies.each do |dep|
            value = @di.resolve(dep)
            job.instance_variable_set(:"@#{dep}", value)
            job.define_singleton_method(dep) { instance_variable_get(:"@#{dep}") }
          end
        end

        # Execute
        # Symbolize args keys for keyword arguments
        symbolized_args = args.transform_keys(&:to_sym)
        result = job.perform(**symbolized_args)

        # Serialize result through JSON round-trip
        serialized = Serialization::Json.decode(Serialization::Json.encode(result))

        record = record.merge(status: :completed, result: serialized, completed_at: Time.now.to_f)
        @backend.save(record)

      rescue => e
        record = @backend.find(id) || {}
        retry_count = (record[:retry_count] || 0) + 1

        if retry_count <= @max_retries
          # Retry
          sleep(@retry_delay) if @retry_delay > 0
          @backend.save(record.merge(retry_count: retry_count, status: :pending))
          @backend.push(job_data)
        else
          # Failed permanently
          error = { message: e.message, backtrace: e.backtrace&.first(10)&.join("\n") }
          @backend.save(record.merge(
            status: :failed,
            error: error,
            retry_count: retry_count,
            completed_at: Time.now.to_f
          ))
          @instrumentation&.emit(:job_failed, { job_id: id, error: error })
        end
      end
    end
  end
end
```

- [ ] **Step 3: Run tests, commit**

```bash
git add lib/whoosh/jobs/worker.rb spec/whoosh/jobs/worker_spec.rb
git commit -m "feat: add Jobs::Worker with execution, DI injection, and retry logic"
```

---

### Task 4: App Integration + CLI Worker Command

**Files:**
- Modify: `lib/whoosh/app.rb`
- Modify: `lib/whoosh/cli/main.rb`
- Create: `spec/whoosh/app_jobs_spec.rb`

- [ ] **Step 1: Write the test**

```ruby
# spec/whoosh/app_jobs_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

class AppTestJob < Whoosh::Job
  def perform(value:)
    { result: value * 2 }
  end
end

RSpec.describe "App jobs integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before do
    application.get "/enqueue" do |req|
      job_id = AppTestJob.perform_async(value: 21)
      { job_id: job_id }
    end

    application.get "/job/:id" do |req|
      record = Whoosh::Jobs.find(req.params[:id])
      if record
        { status: record[:status].to_s, result: record[:result] }
      else
        { error: "not found" }
      end
    end
  end

  it "enqueues jobs from endpoints" do
    get "/enqueue"
    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["job_id"]).to match(/\A[a-f0-9-]+\z/)
  end

  it "finds job status" do
    get "/enqueue"
    job_id = JSON.parse(last_response.body)["job_id"]

    get "/job/#{job_id}"
    body = JSON.parse(last_response.body)
    expect(body["status"]).to eq("pending").or eq("completed")
  end

  it "configures Jobs at boot" do
    app # trigger to_rack
    expect(Whoosh::Jobs.configured?).to be true
  end
end
```

- [ ] **Step 2: Wire Jobs into App**

Read `lib/whoosh/app.rb`. Add private method `auto_configure_jobs` called after `auto_register_http` in initialize:

```ruby
    def auto_configure_jobs
      jobs_config = @config.data["jobs"] || {}
      backend_type = jobs_config["backend"] || "memory"

      backend = case backend_type
      when "memory" then Jobs::MemoryBackend.new
      else Jobs::MemoryBackend.new  # fallback, DB/Redis backends deferred
      end

      Jobs.configure(backend: backend, di: @di)
    end
```

In `to_rack`, after building the rack app but before returning, start in-process workers:

```ruby
        start_job_workers
```

Add private method:

```ruby
    def start_job_workers
      jobs_config = @config.data["jobs"] || {}
      worker_count = jobs_config["workers"] || 2
      max_retries = jobs_config["retry"] || 3
      retry_delay = jobs_config["retry_delay"] || 5

      @job_workers = worker_count.times.map do
        worker = Jobs::Worker.new(
          backend: Jobs.backend,
          di: @di,
          max_retries: max_retries,
          retry_delay: retry_delay,
          instrumentation: @instrumentation
        )
        thread = Thread.new { worker.run_loop }
        thread.abort_on_exception = false
        { worker: worker, thread: thread }
      end

      @shutdown.register do
        @job_workers&.each { |w| w[:worker].stop }
        Jobs.backend&.shutdown
      end
    end
```

- [ ] **Step 3: Add `whoosh worker` CLI command**

Read `lib/whoosh/cli/main.rb`. Add command:

```ruby
      desc "worker", "Start background job worker"
      option :concurrency, aliases: "-c", type: :numeric, default: 2, desc: "Worker threads"
      def worker
        app_file = File.join(Dir.pwd, "app.rb")
        unless File.exist?(app_file)
          puts "Error: app.rb not found"
          exit 1
        end

        require app_file
        whoosh_app = ObjectSpace.each_object(Whoosh::App).first
        unless whoosh_app
          puts "Error: No Whoosh::App instance found"
          exit 1
        end

        concurrency = options[:concurrency]
        puts "=> Whoosh worker starting (#{concurrency} threads)..."

        # Boot the app (configures Jobs)
        whoosh_app.to_rack

        jobs_config = whoosh_app.config.data["jobs"] || {}
        workers = concurrency.times.map do
          w = Whoosh::Jobs::Worker.new(
            backend: Whoosh::Jobs.backend,
            di: Whoosh::Jobs.di,
            max_retries: jobs_config["retry"] || 3,
            retry_delay: jobs_config["retry_delay"] || 5
          )
          Thread.new { w.run_loop }
          w
        end

        trap("INT") { workers.each(&:stop); exit 0 }
        trap("TERM") { workers.each(&:stop); exit 0 }

        sleep
      end
```

- [ ] **Step 4: Run tests, commit**

```bash
git add lib/whoosh/app.rb lib/whoosh/cli/main.rb spec/whoosh/app_jobs_spec.rb
git commit -m "feat: integrate Jobs into App with in-process workers and CLI command"
```

---

### Task 5: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 2: Commit plan**

```bash
git add docs/superpowers/plans/2026-03-17-background-jobs.md
git commit -m "docs: add Background Jobs implementation plan"
```

---

## Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] MemoryBackend with push/pop/save/find and thread-safe access
- [ ] Jobs module with configure/enqueue/find and global backend
- [ ] Job base class with inject DSL and perform_async
- [ ] Worker with execute, DI injection, retry, and status tracking
- [ ] App auto-configures Jobs at boot with in-process workers
- [ ] Shutdown hook stops workers gracefully
- [ ] `whoosh worker` CLI command
- [ ] All existing tests still pass
