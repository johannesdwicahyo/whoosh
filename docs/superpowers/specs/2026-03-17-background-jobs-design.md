# Whoosh Background Jobs Design

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Job definition, queue backends (memory/database/redis), worker execution, status tracking

## Overview

Background job system for async work — fire-and-forget or deferred with status tracking. In-memory queue for dev, database or Redis for production. In-process threads by default, separate `whoosh worker` process for production.

## Job Definition

```ruby
class AnalyzeDocumentJob < Whoosh::Job
  # Declare DI dependencies (resolved from the app's DI container)
  inject :db, :llm

  def perform(document_id:, model: "default")
    doc = db[:documents].where(id: document_id).first
    result = llm.complete("Analyze: #{doc[:text]}")
    { analyzed: true }
  end
end
```

`Whoosh::Job` is the base class. Subclasses implement `perform(**kwargs)`. The return value is stored as the job result.

### DI Injection in Jobs

Jobs declare dependencies via `inject :db, :llm` class-level DSL. When the Worker instantiates a job for execution, it resolves the declared deps from the DI container and sets them as instance variables with accessor methods on the job instance.

```ruby
# Inside Whoosh::Job base class:
class << self
  def inject(*names)
    @dependencies = names
  end

  def dependencies
    @dependencies || []
  end
end

# Worker does:
job = job_class.new
job_class.dependencies.each do |dep|
  value = di_container.resolve(dep)
  job.instance_variable_set(:"@#{dep}", value)
  job.define_singleton_method(dep) { instance_variable_get(:"@#{dep}") }
end
job.perform(**args)
```

Jobs without `inject` have no DI — pure functions of their arguments.

### Queuing

```ruby
# Returns job_id (always)
job_id = AnalyzeDocumentJob.perform_async(document_id: 42)

# Check status
job = Whoosh::Jobs.find(job_id)
job.status  # => :pending | :running | :completed | :failed
job.result  # => { analyzed: true } (nil until completed)
job.error   # => nil or { message: "...", backtrace: "..." }
```

### Global State for `perform_async`

`Whoosh::Jobs` stores the configured backend in a **module-level variable** (`@backend`), set during App boot via `Whoosh::Jobs.configure(backend:, di:)`. This is explicit global state — required because `perform_async` is a class method called outside request context.

If `perform_async` is called before `Jobs.configure`, it raises `Whoosh::Errors::DependencyError, "Jobs not configured — call Whoosh::Jobs.configure or boot a Whoosh::App"`.

### Status Flow

```
pending → running → completed
                  → failed (after max retries exhausted)
```

### Job Record Fields

- `id` — UUID
- `class_name` — job class name string
- `args` — serialized keyword arguments (JSON)
- `status` — pending/running/completed/failed
- `result` — serialized return value (JSON, nil until completed)
- `error` — `{ message:, backtrace: }` (nil unless failed)
- `retry_count` — number of retries attempted
- `created_at` — timestamp
- `started_at` — timestamp (nil until running)
- `completed_at` — timestamp (nil until completed/failed)

## Configuration

```yaml
# config/app.yml
jobs:
  backend: memory      # memory | database | redis
  workers: 2           # thread count
  retry: 3             # max retries on failure
  retry_delay: 5       # seconds between retries
```

## Queue Backends

### Memory Backend

- `Array` protected by `Mutex` + `ConditionVariable` for blocking pop
- Job records stored in a `Hash` by ID
- Lost on restart
- Default — works with zero deps
- **Retry delay:** Worker thread sleeps `retry_delay` seconds before re-queuing. This blocks that worker thread during the delay — acceptable for dev/testing but documented as a throughput limitation.

### Database Backend

- Uses Sequel (already optional dep) via the app's `:db` DI dependency
- **Table creation at App boot** (synchronous, before worker threads start) — not lazy/first-use. Uses `CREATE TABLE IF NOT EXISTS`. No race condition because it runs in the single-threaded boot phase.
- Jobs persist across restarts
- Polling-based: workers poll every 1 second for new jobs
- Config: `backend: database`

### Redis Backend

- Uses `redis` gem (already optional dep from cache)
- `LPUSH`/`BRPOP` for queue operations
- Job records stored as Redis hashes
- Config: `backend: redis`, reads `cache.url` or separate `jobs.redis_url`

## Worker Execution

### In-Process Mode

- Worker threads start automatically when the App boots (in `to_rack`)
- Number of threads from `jobs.workers` config (default: 2)
- Threads run a loop: pop job from queue → set status to running → resolve DI deps → call `perform` → set status to completed/failed
- On failure: increment retry_count, if < max retries, sleep `retry_delay` then re-queue. Otherwise set status to failed.
- Threads are daemon threads — they stop when the main process exits
- Shutdown hook registered via `@shutdown.register` to signal workers to stop (set a `@running = false` flag, signal the ConditionVariable)

### Separate Worker Process

```bash
whoosh worker              # starts worker with config defaults
whoosh worker -c 4         # 4 threads
```

- Loads `app.rb` and finds the Whoosh::App instance via ObjectSpace
- Calls `app.boot_workers!` — a dedicated method that:
  1. Loads .env and config
  2. Initializes DI container
  3. Configures `Whoosh::Jobs` with the backend
  4. Creates DB table if database backend
  5. Starts worker threads
  6. Installs signal handlers (SIGTERM/SIGINT → graceful stop)
  7. Blocks the main thread until shutdown
- Does NOT build the Rack app or start a web server

## App Integration

```ruby
# In endpoints
app.post "/analyze" do |req|
  job_id = AnalyzeDocumentJob.perform_async(document_id: req.body["id"])
  { job_id: job_id }
end

app.get "/jobs/:id" do |req|
  job = Whoosh::Jobs.find(req.params[:id])
  { status: job.status, result: job.result, error: job.error }
end
```

- `Whoosh::Jobs` is the module-level API: `.configure(backend:, di:)`, `.enqueue(job_class, **args)`, `.find(id)`
- `Whoosh::Job` base class provides `.perform_async(**args)` which delegates to `Jobs.enqueue`
- `Jobs.configure` called during App boot with the selected backend and DI container reference

## Error Handling

- Job `perform` raises → caught by worker → retry or fail
- Error stored as `{ message: exception.message, backtrace: exception.backtrace.first(10).join("\n") }`
- Backtrace truncated to 10 lines
- Failed jobs stay in the store for inspection (not auto-deleted)
- Instrumentation event emitted on failure: `instrumentation.emit(:job_failed, { job_id:, error: })`

## Files

### New Files

| File | Purpose |
|------|---------|
| `lib/whoosh/job.rb` | Base job class with `perform_async` and `inject` DSL |
| `lib/whoosh/jobs.rb` | Module API: configure, enqueue, find |
| `lib/whoosh/jobs/memory_backend.rb` | In-memory queue + store |
| `lib/whoosh/jobs/worker.rb` | Worker thread loop with retry and DI resolution |
| `spec/whoosh/jobs_spec.rb` | Job definition and queuing tests |
| `spec/whoosh/jobs/memory_backend_spec.rb` | Memory backend tests |
| `spec/whoosh/jobs/worker_spec.rb` | Worker execution tests |

### Modified Files

| File | Change |
|------|--------|
| `lib/whoosh.rb` | Add autoloads for Job, Jobs |
| `lib/whoosh/app.rb` | Configure Jobs at boot, start in-process workers in to_rack |
| `lib/whoosh/cli/main.rb` | Add `whoosh worker` command |

## Dependencies

- No new hard dependencies
- `sequel` — optional, for database backend (already optional dep)
- `redis` — optional, for Redis backend (already optional dep)
