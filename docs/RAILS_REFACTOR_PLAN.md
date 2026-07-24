# Full-Rails Refactor Plan

Retiring the Python translation pipeline (`src/` + 9 root scripts, ~5,600 LOC)
in favor of an all-Ruby stack. Not a roadmap item — discretionary architecture
work.

**Status as of 2026-07-24: R0.5 and R0.1 done, R0.2–R0.4 still to build.**
All five R0 milestones below have reviewed Goal/Design/Acceptance-criteria
sections. R1–R7 are still at the summary level in the artifact linked below;
they have not been given the same detailed treatment.

**To resume with implementation, start here:** R0.2 (second Kamal role for
Solid Queue) is next in build order. Go in order R0.2 → R0.3 → R0.4; each
section is self-contained. The one non-code step is R0.3, which needs
someone with actual access to the production Oracle VM to run its
measurement procedure — everything else can be implemented and reviewed
without that.

**Full original plan, diagrams, and pros/cons (R1–R7, superseded for R0
specifics by the detailed sections below):**
https://claude.ai/code/artifact/31286d3b-7c57-4c47-a3d2-c2675944ed11

## Summary

- **R0 — Infra foundation** (before any pipeline logic moves): a timeout-safe
  subprocess primitive, a dormant second Kamal role for Solid Queue, a
  deferred memory-baseline task, a `PIPELINE_IMPL` migration toggle, an RSpec
  CI job.
- **R1–R3** — backend seam, `bible_lookup` going in-process, skill bridge
  onto the official `mcp` gem (`modelcontextprotocol/ruby-sdk`). Low risk,
  worth doing regardless of R4+.
- **R4–R6** — port the prompt builders and response parsers (preread,
  translator, formatter, bible_review, voice_calibration, OCR). The real
  commitment — correctness-critical string logic, needs input-level diffing
  against real chapters before cutover.
- **R7** — delete the Python layer (`venv/`, `requirements.txt`, Dockerfile
  stage), revisit the now-obsolete "`ANTHROPIC_API_KEY` stays in `.env`"
  decision.

Current recommendation: land R0 → R1–R3 now; stage R4–R6 behind finishing
Phase 5.

Each milestone below is written as **Goal / Design / Acceptance criteria** so
the roadmap doubles as an implementation checklist. Build order for R0 is
**R0.5 → R0.1 → R0.2 → R0.3 → R0.4** — CI enforcement lands first so nothing
after it ships untested; R0.1 next since R0.2–R0.4 don't depend on it but
benefit from the same discipline being fresh.

## R0 — Infra foundation

### R0.5 — RSpec enforced in CI

**Status: done (`.github/workflows/ci.yml`, commit e6f3244).** CI is
currently red: the suite has 58 pre-existing failures (stale auth specs
that assume a login/OAuth flow which doesn't exist since auth is
disabled, plus a handful of real bugs like `bible_locations` redirecting
to `edit` instead of `show`) unrelated to this milestone. Fixing those is
separate follow-up work, not part of R0.

- **Goal:** Make RSpec a required, enforced gate in CI — not just runnable.
  Neither RSpec nor the Python `tests/` suite runs in CI today; `ci.yml` only
  covers Brakeman, bundler-audit, `importmap audit`, and Rubocop.
- **Design:** New `test` job in `.github/workflows/ci.yml`, parallel to the
  existing four. Postgres service container with a health check, matching
  the `postgresql` adapter in `config/database.yml`. `bundler-cache: true`,
  matching the pattern already used by `scan_ruby`/`scan_js`/`lint`. Steps:
  checkout → `ruby/setup-ruby` → `bin/rails db:prepare` (not a
  test-only `db:test:prepare`/`schema:load` — deliberately the same command
  dev/production use, so CI stays close to how the app is actually run) →
  `bundle exec rspec`. `db:prepare` already fails on a schema/migration
  mismatch, so no separate pending-migrations check is needed as long as
  `schema.rb` stays committed and current. `webmock/rspec` is already
  required in `rails_helper.rb`, so no additional HTTP-blocking setup is
  needed for R1's Faraday calls later.
  Deliberately out of scope: splitting into parallel unit/integration jobs
  (premature at current suite size), and adding the Python `tests/` suite to
  CI (separate decision from "RSpec is enforced").
- **Acceptance criteria:**
  - `test` job exists in `ci.yml` and runs on every PR and push to `main`.
  - **CI fails if any RSpec example fails** — the job's actual job, not
    merely that RSpec can be invoked.
  - `bin/rails db:prepare` runs against a real Postgres service container in
    the workflow, not a stub.
  - Gems are cached via `bundler-cache: true`.

### R0.1 — `Pipeline::Subprocess.run`

**Status: done** (`app/services/pipeline/subprocess.rb`,
`app/services/pipeline_dispatcher.rb`). `PipelineDispatcher#execute` now
calls `Pipeline::Subprocess.run` with a 4-hour timeout (matching
`PipelineJob`'s own local-LLM concurrency-limiter window) and no
`cancel_token` — wiring actual cancellation into Solid Queue is the "small
adapter" work explicitly deferred to a later milestone, not required here.
`format_korean_chapter_job.rb` and `ocr_chapter_job.rb` still have their own
hand-rolled top-pid-only `Open3.popen3` timeout logic — deliberately
untouched, since the design's scope boundary is `PipelineDispatcher#execute`
only. Migrating those two is a candidate follow-up, not part of R0.1.

- **Goal:** Replace direct, timeout-less `Open3.capture3` usage in
  `PipelineDispatcher#execute` with a robust subprocess execution primitive
  that every later phase's subprocess forks (the `claude` CLI call after R1,
  the MCP bridge after R3) can reuse without re-solving timeout/signal
  correctness each time.
- **Design:**
  - **Scope boundary:** touches only `PipelineDispatcher#execute` — the
    private method that currently wraps `Open3.capture3`. Routing on
    `job_type` and building each script's argv stays in `PipelineDispatcher`
    unchanged; splitting that into a real orchestration layer
    (`TranslationPipeline` → `ClaudeTranslator` → `Subprocess.run`) is R1's
    job, once the backend seam (local Ollama vs. `claude_code`) actually
    exists in Ruby and there's something to hang that layer off of.
  - **API:** `Pipeline::Subprocess.run(cmd, env:, timeout:, cancel_token: nil, name:)`.
    `cmd`/`env` are fully built by the caller — `Subprocess.run` never knows
    or cares whether it's running Python, the `claude` CLI, or an MCP
    server; no `run_claude`/`run_python` methods. `name:` is a short label
    for logging (e.g. `"translate_batch"`), decoupled from the argv itself.
  - **Result object** — replaces today's `[stdout, stderr, success?]` triple:

    | field | type | notes |
    |---|---|---|
    | `status` | `:completed \| :timed_out \| :cancelled` | purely "how execution ended" — never extended with `:failed`/`:success`, which would overlap with `exit_code` |
    | `exit_code` | `Integer \| nil` | nil only when the process was killed before it could exit on its own |
    | `success?` | derived | `status == :completed && exit_code == 0` — a convenience predicate, not the source of truth |
    | `started_at`, `finished_at` | `Time` | cheap to capture now, awkward to retrofit once log formats depend on them; useful for correlating logs across systems later, not just computing duration |
    | `duration` | `Float` | `finished_at - started_at`, kept as its own field for metrics code |
    | `command_name` | `String` | the `name:` label only — never full argv |
    | `bytes_stdout`, `bytes_stderr` | `Integer` | |

    State space:

    | status | exit_code | meaning |
    |---|---|---|
    | `completed` | `0` | success |
    | `completed` | nonzero | ran, child errored |
    | `timed_out` | `nil` | killed after deadline |
    | `cancelled` | `nil` | killed via `cancel_token` |

  - **Process groups:** `Process.spawn(env, *cmd, pgroup: true, ...)`.
    `claude` or a Python script may fork children of its own; signaling only
    the top pid would leave those orphaned. Timeout/cancellation send
    SIGTERM to the process group, wait a short grace period, then SIGKILL
    the group if still alive.
  - **Reader threads:** stdout/stderr drained concurrently on separate
    threads into buffers while a poll loop waits on the pid, to avoid
    pipe-buffer deadlock on output larger than the OS pipe buffer. Poll
    interval is **fixed, ~50–100ms, not adaptive** — subprocess wait latency
    doesn't need sub-100ms precision, and a fixed interval is one less thing
    to get wrong.
  - **Cleanup path** is as explicit as the happy path: spawn → start readers
    → wait loop → `ensure` block that joins readers and closes descriptors
    unconditionally, whether the wait loop exited via natural completion,
    timeout-kill, cancellation-kill, or a raised exception.
  - **Cancellation ownership:** token-based, caller-agnostic.
    `cancel_token` is just an object `Subprocess.run` polls via
    `.cancelled?` — it has no idea Solid Queue exists. Whatever wants to
    cancel (a Solid Queue shutdown hook, a rake task's own
    `Signal.trap`, a future web-triggered "stop this job" action) sets the
    flag on its own terms. The Solid Queue wiring (how a worker shutdown
    actually flips the token for an in-flight `PipelineJob`) is a small
    adapter written once R0.1 lands — not something the primitive itself
    needs to know about, and not resolved in this document.
  - **Retry — deliberately absent.** `Subprocess.run` executes once and
    reports what happened; it does not loop or back off internally. Retry
    policy varies per job type and belongs in the orchestration layer above.
  - **Logging/security constraint:** never log full `cmd` or `env` — only
    `command_name`, `duration`, `exit_code`/`status`, and byte counts.
    `PipelineDispatcher` today forwards the entire parent `ENV` (including
    `RAILS_MASTER_KEY`, `DATABASE_URL`) into every subprocess; the logging
    layer must not make that worse by writing it to structured logs.
- **Acceptance criteria:**
  - No remaining direct `Open3.capture3` calls in pipeline code —
    `PipelineDispatcher#execute` goes through `Pipeline::Subprocess.run`.
  - A timeout terminates the entire process group, not just the top pid.
  - Stdout/stderr are fully drained regardless of output size or exit path.
  - Every subprocess exit — natural, timed-out, or cancelled — produces a
    `Result` with a value in the state-space table above; no other
    `status`/`exit_code` combination is reachable.
  - Existing `PipelineDispatcher` callers continue working with equivalent
    behavior (same effective `[stdout, stderr, success?]` semantics via
    `Result#success?`), with no `PipelineJob` behavior change required for
    this milestone specifically.
  - Logs for a subprocess run never contain full `cmd`, `env`, `stdout`, or
    `stderr` content — only `command_name` + numeric/status fields.

### R0.2 — Second Kamal role for Solid Queue

**Status: design finalized, ready to build.**

- **Goal:** Add a `jobs` role to `config/deploy.yml` that is **deployable
  and operationally isolated today** — it boots, it can be monitored, it
  doesn't receive HTTP traffic, and it doesn't change the application's
  intended execution model. `SOLID_QUEUE_IN_PUMA` stays `true`. The point is
  proving the role works now (`kamal deploy` succeeds, `bin/jobs` boots
  Solid Queue standalone) rather than discovering it doesn't the day memory
  pressure forces the switch.
- **Design:**
  - `servers.jobs` in `config/deploy.yml` — same host as `web` (one Oracle
    micro instance, no new hardware), `cmd: bin/jobs` (already exists,
    unmodified — just `SolidQueue::Cli.start`), `proxy: false`.
  - Shares the `hawk_storage` volume (Active Storage — `PipelineJob#attach_translated_outputs`
    writes into it) and the existing `env.secret`/`env.clear` blocks. No new
    secrets or role-specific env needed. Novel source content
    (`idols-rewind/`, etc.) is already baked into the image via `COPY . .`
    in the Dockerfile, so the second role has it for free without a
    separate mount.
  - **Healthcheck, confirmed:** non-proxied roles don't get the `/up` HTTP
    check — that's specific to proxied web roles. With no Docker health
    check configured, Kamal waits for the container to reach the running
    state (optionally with a `readiness_delay`); it only waits for
    `healthy` if a Docker health check is explicitly configured. So:
    `web` → proxied → `/up`; `jobs` → non-proxied → container running-state
    is sufficient, no HTTP check to design.
  - **Puma-plugin / standalone interaction, verified against the
    `solid_queue` 1.3.2 gem source:** the Puma plugin
    (`lib/puma/plugin/solid_queue.rb`) forks and calls
    `SolidQueue::Supervisor.start(mode: :fork)` — the exact same call
    `bin/jobs` makes, with no special-casing for whether another supervisor
    exists. `Supervisor#start_processes` just starts whatever
    `config/queue.yml` configures for that process; job claiming is
    coordinated at the database layer (workers poll and lock rows), not
    between supervisors. So if `SOLID_QUEUE_IN_PUMA=true` and the `jobs`
    role were both active at once, the result is **two independent sets of
    dispatchers/workers pulling from the same queues — additional capacity,
    not duplicate execution.** The real risk of running both is resource
    usage (connections, memory, CPU), not correctness. This is documented
    here as an explicitly **unsupported deployment topology for now** —
    R0.2 does not enable both; that decision is R0.3's trigger-based
    cutover to make.
- **Acceptance criteria:**
  - `config/deploy.yml` defines a `jobs` role.
  - The role starts with `bin/jobs`.
  - The role is non-proxied (`proxy: false`), with no HTTP healthcheck
    configured — container running-state is the readiness signal.
  - The role mounts the same `hawk_storage` volume as `web`.
  - The role receives the same application secrets as `web`.
  - `kamal deploy` succeeds with both roles defined.
  - Production behavior is unchanged — `SOLID_QUEUE_IN_PUMA` stays `true`,
    so the current worker topology (Puma-embedded only) remains the only
    one actually processing jobs until a later milestone flips it.
  - The Puma-plugin/standalone-`jobs` interaction (additional capacity, not
    duplicate execution; unsupported to run both simultaneously today) is
    written down in this document, not left as tribal knowledge.

### R0.3 — Memory baseline & trigger rule

**Status: design finalized, ready to build. Measurement itself is a
follow-up execution step — it requires access to the actual Oracle VM,
which this design process didn't have; what's finalized here is the
procedure, not the resulting numbers.**

- **Goal:** Measure representative worst-case workloads, not synthetic
  stress tests — turn "watch memory" into an actual decision procedure by
  measuring the real cost of the two heaviest pipeline paths and writing a
  trigger rule for flipping `SOLID_QUEUE_IN_PUMA` off and activating the
  R0.2 `jobs` role.
- **Design:**
  - **Measure two numbers per workload, not one** — a real
    `translate_batch` job and a real `ocr_chapter` job, each measured
    two ways:
    - **Peak container memory** (operational) — from `docker stats` or
      `/sys/fs/cgroup/memory.peak`, the whole container's footprint against
      its actual 1GB ceiling. This is the number the kernel actually
      enforces, so it's the right basis for the flip decision — but it's
      noisy for understanding pipeline cost specifically, since it also
      reflects Puma GC timing, Active Storage caching, and other
      application noise unrelated to the translation/OCR work itself.
    - **Peak subprocess-tree RSS** (diagnostic) — the entire process tree
      rooted at the spawned Python PID (interpreter + forked `claude` CLI
      child). Isolates "how expensive is translation/OCR" from Rails/Puma
      noise. Doesn't need to be exact — even an approximate sum across the
      tree beats a single-process reading, which would undercount whenever
      the forked `claude` CLI is the heavier consumer.
  - **Decision rule stays based on container memory alone.** The
    subprocess-tree number is for understanding cost, not for triggering
    the flip — keeps "how expensive is the pipeline" separate from "will
    the box OOM."
  - **Reproducibility:** record the exact input workload alongside each
    number — chapter count and approximate token count for the translation
    run, page/image count for the OCR run. Without this, a benchmark rerun
    months later against a differently-sized chapter produces a number
    that looks like drift but is actually just a different workload.
  - **Trigger rule**, a disjunction:
    - **Sustained pressure:** container memory above threshold `N` for `M`
      consecutive minutes, `N`/`M` set relative to the measured baseline so
      one job's normal peak doesn't false-trigger on its own.
    - **Repeated OOM events** — `exit_code == 137` (SIGKILL) is
      **supporting evidence, not the authoritative signal.** SIGKILL can
      come from the kernel OOM-killer, an operator's manual `kill -9`, or
      Docker killing the container — exit code alone can't distinguish
      them. The condition is "repeated kernel or container OOM events,
      corroborated via `dmesg`/kernel logs or Docker events," with exit
      code 137 as one input to that determination during the manual
      procedure, not the definition of it.
  - **Explicitly not in scope:** building automated monitoring/alerting.
    R0.3 answers "when do we flip," not "how do we automate flipping" —
    those are different milestones.
- **Acceptance criteria:**
  - Both peak container memory and peak subprocess-tree RSS are measured
    and recorded for a real `translate_batch` run and a real `ocr_chapter`
    run, on the actual Oracle VM (not estimated, not synthetic).
  - The exact input workload for each measurement (chapter count,
    approximate token count / page-image count) is documented alongside
    the numbers, so the benchmark is reproducible rather than a one-off
    unexplained figure.
  - A trigger rule is written as a concrete disjunction — sustained
    container memory above `N` for `M` minutes, OR repeated kernel/container
    OOM events confirmed via `dmesg`/Docker events (exit code 137 treated as
    supporting evidence only) — and the flip decision is based on container
    memory, not subprocess-tree RSS.
  - The dependency on `PipelineJob` persisting `exit_code`/`status` (from
    R0.1's `Result`) is named explicitly as needed supporting data for the
    OOM condition, not assumed already captured.
  - No new monitoring/alerting infrastructure is built as part of this
    milestone.

### R0.4 — `PIPELINE_IMPL` toggle

**Status: design finalized, ready to build.**

- **Goal:** Make each job type's pipeline implementation (legacy Python
  script vs. new in-process Ruby service, once R1–R6 land one) independently
  selectable and revertible, so those phases ship as a sequence of small,
  reversible changes instead of one cutover.
- **Design:**
  - **One env var per job type, not one parameterized var** —
    `PIPELINE_IMPL_PREREAD`, `PIPELINE_IMPL_TRANSLATE_BATCH`,
    `PIPELINE_IMPL_BIBLE_BUILD`, `PIPELINE_IMPL_POST_TRANSLATION_REVIEW`,
    `PIPELINE_IMPL_VOICE_CALIBRATION`. This mirrors the codebase's own
    existing idiom rather than inventing a new one: `config.py` already has
    two independent axes — `TRANSLATION_BACKEND` and
    `CALIBRATION_BACKEND` — as two separate env vars, not one var carrying
    a parsed mapping. **Why per-job-type rather than one global switch:**
    each job type migrates on its own release cadence — R1–R6 land one
    job type's Ruby port at a time, on its own schedule, and flipping one
    shouldn't require touching the others. Stated here explicitly so the
    five-var surface reads as an intentional migration tool, not
    accidental configuration sprawl.
  - **Values:** `"python"` (default) or `"ruby"`. Default is `"python"` for
    every job type — deploying R0.4 itself changes zero production
    behavior. An unrecognized value raises a clear configuration error
    rather than silently falling back to `"python"` — a typo like `rby`
    should be loud, not a silent wrong-backend footgun.
  - **Parsing centralized in one place** — `PipelineImplementation.for(job_type)`,
    returning `:python`/`:ruby` (or raising on an invalid value). This is
    the only place a `PIPELINE_IMPL_<TYPE>` string literal gets read and
    validated; nothing downstream re-parses or re-checks it, so the
    validation logic exists exactly once instead of a little `case`
    creeping into every call site.
  - **Configuration lookup stays separate from routing.** `PipelineDispatcher#call`
    resolves `PipelineImplementation.for(@job.job_type)` once, then
    dispatches — not a case nested inside a case:

    ```
    implementation = PipelineImplementation.for(@job.job_type)
    case implementation
    when :python then dispatch_python   # existing per-job-type case, unchanged
    when :ruby   then dispatch_ruby     # new per-job-type case
    end
    ```

    Two flat per-job-type dispatch tables, not one interleaved structure —
    configuration lookup and routing are different responsibilities and
    stay legible as separate ones. Not a full registry — that would be
    over-building for what R0.4 actually needs.
  - **Ruby implementations exist from day one, even as stubs — the
    dispatcher never changes again after R0.4.** Rather than
    `dispatch_ruby`'s branches raising `NotImplementedError` inline, each
    job type gets a real stub class from R0.4 onward (e.g.
    `Pipeline::Ruby::TranslateBatch.call(@job)`) that raises
    `NotImplementedError` *internally*. R1–R6 then only ever change what's
    behind that seam — `PipelineDispatcher`'s structure and
    `dispatch_ruby`'s branches are done after R0.4 and don't get touched
    again, which keeps each of R1–R6 a smaller, more contained PR.
  - **Relationship to `TRANSLATION_BACKEND`/`CALIBRATION_BACKEND`:**
    orthogonal axis, documented with a concrete example so it isn't
    forgotten six months from now:

    | `TRANSLATION_BACKEND` | `PIPELINE_IMPL_TRANSLATE_BATCH` | Result |
    |---|---|---|
    | `ollama` | `python` | Python pipeline runs, using Ollama |
    | `ollama` | `ruby` | Ruby implementation owns backend selection itself — `TRANSLATION_BACKEND` is ignored for this job type |

  - **These are migration flags, not permanent configuration.** Stated
    explicitly rather than left to infer: feature flags introduced for a
    migration have a habit of quietly becoming permanent API. All five
    `PIPELINE_IMPL_<TYPE>` vars are expected to be retired once every job
    type has a stable Ruby implementation — they're scaffolding for R1–R6,
    not a long-term architectural feature. Retiring them isn't required
    the moment R6 lands, but the expectation is set now rather than
    discovered later.
- **Acceptance criteria:**
  - Every pipeline job type has an implementation selector
    (`PipelineImplementation.for(job_type)`), with validation happening in
    exactly one place.
  - Unset defaults to `"python"` for every job type — deploying this
    milestone changes zero production behavior.
  - A value other than `"python"`/`"ruby"` fails loudly (at lookup, not
    silently) rather than defaulting.
  - Changing one job type's implementation selector does not affect any
    other job type's dispatch or config.
  - Switching a job type between implementations requires only
    configuration, not a code change — the stub Ruby class for that job
    type already exists.
  - A stub Ruby implementation class exists for every job type from this
    milestone onward, each raising `NotImplementedError` internally.
    `PipelineDispatcher`'s dispatch structure does not change again across
    R1–R6 — only the stubs' internals do.
  - The orthogonal relationship to `TRANSLATION_BACKEND`/
    `CALIBRATION_BACKEND` is documented with a worked example, not left
    implicit.
  - The design doc states plainly that these env vars are temporary
    migration scaffolding, expected to be retired once all job types have
    stable Ruby implementations.

---

**R0 is now fully designed (R0.1–R0.5), in build order R0.5 → R0.1 → R0.2 →
R0.3 → R0.4.** Each has a Goal/Design/Acceptance-criteria section above
ready to implement. R0.3's acceptance criteria depend on measurement access
to the production VM, which wasn't available during this design pass — that
execution step remains open. Next up, when picked up: R1 (backend seam).
