# Full-Rails Refactor Plan

Retiring the Python translation pipeline (`src/` + 9 root scripts, ~5,600 LOC)
in favor of an all-Ruby stack. Not a roadmap item — discretionary architecture
work.

**Status as of 2026-07-24: R0.5, R0.1, and R0.4 done. R0.2's config is
written but not deployed. R0.3 is explicitly skipped — see below. R1's
infra (env var contract, subprocess secrets policy, credential/network
reachability), R2's `bible_lookup` in-process design, and R3's skill-bridge
design (onto the official `mcp` gem) are all fully designed, with no Ruby
implementation code written for any of them yet — see the R1, R2, and R3
sections below.**
All five R0 milestones, plus R1's, R2's, and R3's design sections, have
reviewed Goal/Design/Acceptance-criteria sections. R4–R7 are still at the
summary level in the artifact linked below; they have not been given the
same detailed treatment.

**R0.3 skipped, not just blocked:** R0.3's whole premise is measuring real
peak container memory on the production Oracle VM under real workloads.
That presupposes hawk-translations is actually deployed and running
there. It isn't — confirmed 2026-07-24, hawk-translations currently runs
only locally via systemd (`install-service.sh`), not on Oracle. "Needs VM
access" was the wrong framing; there is no production instance to measure
yet. R0.3 is skipped by user decision rather than deferred pending access —
revisit it only once R0.2's `kamal deploy` actually happens and a real
production instance exists to measure.

**To resume:** R0.2's `config/deploy.yml` change still needs an actual
`kamal deploy` run against production to confirm the `jobs` role boots
there — a deliberately separate, deploy-triggering step from writing the
config itself. With R0.3 skipped, R0 is otherwise closed. R1's infra, R2's
`bible_lookup` design, and R3's skill-bridge design are all now designed
(see the R1, R2, and R3 sections below); writing the actual Ruby code for
any of them is the next build step.

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

**Status: config written (`config/deploy.yml`), not deployed.**
`bin/kamal config` resolves both `web` and `jobs` roles correctly (verified
locally, no VM access needed for this check). Actually running
`kamal deploy` against the production Oracle VM to confirm the role boots
there is a deliberately separate, deploy-triggering step — not run as part
of this pass. `SOLID_QUEUE_IN_PUMA` stays `true`; no production behavior
changes until that deploy happens.

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

**Status: skipped (2026-07-24), design kept below for when it's picked
back up.** Not blocked-pending-access — the design presupposes
hawk-translations is already deployed and running on the production
Oracle VM, which it isn't (it runs locally via systemd today; the R0.2
Kamal role has never actually been deployed). There's no production
instance yet to measure. Revisit only once a real `kamal deploy` happens.

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

**Status: done** (`app/services/pipeline_implementation.rb`,
`app/services/pipeline/ruby/*.rb`, `PipelineDispatcher#call` now resolves
`PipelineImplementation.for(@job.job_type)` and routes through
`dispatch_python`/`dispatch_ruby`). All five `PIPELINE_IMPL_<TYPE>` vars
default to `"python"`; a stub `Pipeline::Ruby::*` class exists for every
job type, each raising `NotImplementedError` internally. R1-R6 change only
those stubs' internals from here on.

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
ready to implement. R0.3 is explicitly skipped (see status note at the top
of this document) rather than pending measurement access.

## R1 — Backend seam infra

**Status: designed (2026-07-24), revised same day after review. No Ruby
code written yet.** This section is deliberately infra-only — env var
contract, subprocess secrets policy, credential/network reachability —
settled before `Pipeline::Ruby::TranslateBatch` or any other stub's
internals get written. That build step is separate, later work.

- **Goal:** Settle every infra-level decision the backend seam (Ollama vs.
  `claude_code`, in Ruby) depends on before any Ruby implementation exists,
  so that later build step has nothing left to decide except the code itself.
- **Layering, stated explicitly:** Infra (this section, R1) → backend
  adapter (R1's actual code, later) → translation pipeline (R4+). R1 owns
  none of the translation/prompt logic — only how a backend gets invoked
  safely. Written down so R1's scope doesn't quietly grow into R4's.
- **Design:**
  - **Env var contract: reuse Python's names verbatim, invent nothing new.**
    `TRANSLATION_BACKEND` (`"local"` | `"claude_code"`, default
    `"claude_code"`), `CALIBRATION_BACKEND` (same two values, independent
    axis), `LLM_BASE_URL` (default `http://localhost:11434/v1`),
    `LLM_API_KEY` (default `"local"`), `TRANSLATION_MODEL`,
    `TRANSLATION_MAX_BUDGET_USD`, `CLAUDE_BIN` (default `"claude"`).
    Precedent already exists: `PipelineJob.local_llm_endpoint?`
    (`app/jobs/pipeline_job.rb:7-17`) already reads `LLM_BASE_URL` from ENV
    today, on the Ruby side, to decide Solid Queue concurrency — Ruby and
    Python already share this var's name and default. R1 extends that same
    contract to the rest of the list rather than introducing Ruby-prefixed
    duplicates (no `HAWK_TRANSLATION_BACKEND`).
    - **Requirement for R1's build (not code here, a constraint on the
      code):** one validated read point, not scattered `ENV.fetch` calls.
      `TRANSLATION_BACKEND`/`CALIBRATION_BACKEND` checked against
      `%w[local claude_code]`, raising on anything else — same discipline
      R0.4 already promised for `PIPELINE_IMPL_*`, extended here.
      `TRANSLATION_MAX_BUDGET_USD` parsed as a non-negative decimal, not
      used as a raw string. Whether this lives in one `TranslationConfig`-
      style object or elsewhere is a code decision for R1's build, not
      settled in this doc.
    - Naming clash to flag, not fix here: `PipelineDispatcher::PYTHON`
      already exists as an unrelated Ruby constant (`ENV.fetch("PYTHON",
      "python3")`, the interpreter binary — an R0.4-era leftover, itself a
      candidate for deletion once `dispatch_python` has no callers left).
      Noted so it isn't confused with `TRANSLATION_BACKEND`/
      `CALIBRATION_BACKEND` when R1 is actually built.
  - **`claude` CLI invocation — no shell, argv array only.** Matches
    `Pipeline::Subprocess.run`'s existing design (R0.1) and
    `PipelineDispatcher`'s existing array-based `Open3` calls — stated
    explicitly here so it can't quietly regress into a shell-interpolated
    string later. No `system("claude #{prompt}")`-shaped code, ever.
  - **`CLAUDE_BIN` resolution — resolved once, to an absolute path, before
    any subprocess spawn.** If unset, the default `"claude"` is resolved via
    a `PATH` lookup performed by the Rails process's own controlled
    environment — once, not per-request, and not delegated to the child.
    The resolved value is always an absolute path, used directly as
    `argv[0]`. If `CLAUDE_BIN` is set, it must already be an absolute,
    executable path — no further `PATH` search on top of it. Because
    `Process.spawn` given an absolute-path executable does not re-search
    `PATH` to find it, **`PATH` is dropped from the child's env entirely** —
    correcting the original draft of this section, which listed `PATH` as
    something forwarded to the subprocess. Without this, anything able to
    modify the parent process's `PATH` could redirect a bare `"claude"`
    lookup to an attacker-controlled binary; resolving to an absolute path
    up front removes that dependency completely.
  - **Subprocess env allowlist for the `claude` CLI fork, revised: `HOME`
    and `MCP_CONNECTION_NONBLOCKING=false` only.** (`CLAUDE_BIN` is
    consumed by Ruby to choose `argv[0]` — it is not itself forwarded as a
    child env var.) `MCP_CONNECTION_NONBLOCKING=false` is the same
    undocumented startup-race workaround `claude_code_agent.py:114` sets
    today — carries over unchanged. `HOME`'s inclusion is documented here
    rather than left implicit: it exists **solely** because the `claude`
    CLI stores its OAuth/session state under the user's home directory.
    Named tradeoff, not hidden: `HOME` also reaches `~/.ssh`, `~/.aws`,
    `~/.gitconfig`, and anything else namespaced under it — accepted for
    now because the CLI doesn't expose a narrower, credential-only
    directory to point `HOME` at instead. Today `PipelineDispatcher#execute`
    (R0.1, already shipped) instead calls `Pipeline::Subprocess.run` with
    `env: ENV.to_h.merge(...)` — full-`ENV` forwarding, the opposite of this
    allowlist. **Flagged as required cleanup for R1's actual build, not
    silently changed here** — R1's implementation should replace that
    call's env construction with this allowlist, built additively from
    `{}` rather than deleting keys from a full copy of `ENV` (a deny-list
    is one missed key away from a leak; an allow-list built from empty
    can't leak what it never included).
  - **Stdin carries the prompt — not closed.** Checked against
    `claude_code_agent.py:117-125`: the CLI call already pipes
    `user_message` via `stdin` (`subprocess.run(cmd, input=user_message,
    ...)`), while the system prompt goes through `--system-prompt-file`
    specifically to avoid `ARG_MAX`/shell-escaping issues on large prompts.
    R1's Ruby call keeps this shape — stdin is the message-delivery
    channel, not something to close.
  - **Secrets inventory — explicit list, not "everything except one key."**
    Must never reach the `claude` CLI subprocess env: `RAILS_MASTER_KEY`,
    `DATABASE_URL`, `ANTHROPIC_API_KEY`, and anything matching
    `*_SECRET`/`*_KEY`/`*_TOKEN`. Written down so a future secret added to
    `.env` doesn't silently become reachable through a carelessly widened
    allowlist later.
  - **Failure taxonomy — categories, not implementation.** Binary not
    found or not executable; OAuth session missing or expired; timeout
    (R0.1's existing `:timed_out` status); nonzero exit; unparseable JSON
    output; killed by OOM. Listed here so whoever writes R1's error
    handling has a fixed set of buckets to map onto, rather than
    discovering them ad hoc.
  - **`claude` CLI OAuth credential availability — out of scope for R1,
    same reasoning as R0.3.** The CLI authenticates via a subscription
    OAuth session (`claude auth login`) already present on this local dev
    machine. Local OAuth credentials are a developer-machine concern today,
    not part of the application's own configuration surface — Rails does
    not authenticate Claude, it only inherits whatever session already
    exists on the host it runs on. R1 targets the same locally-run systemd
    process every other job type already runs under (see
    [[hawk_translations_shared_oracle_vm]]) — there's no deployed instance
    to authenticate on yet. If hawk-translations is ever actually `kamal
    deploy`'d, the container would need its own authenticated session (a
    credential volume mount, or an unattended `claude auth login
    --no-browser`) — the same open question already parked for
    forex_backtester's Console-billing fix (see
    [[hawk_translations_claude_code_headless_backend]]). Not solved here;
    flag it if a real deploy is ever scheduled.
  - **Ollama reachability — no new infra.** `LLM_BASE_URL` already resolves
    to a loopback/private address today, and `PipelineJob.local_llm_endpoint?`
    already serialises Solid Queue jobs to 1 concurrent
    (see [[hawk_translations_local_llm_memory_limit]] — one `gpt-oss-20b`
    load at a time or WSL OOMs). R1's Ruby `"local"` backend reuses this
    existing constraint rather than needing a new concurrency mechanism.
    This is a **local-hardware** constraint (one GPU/box) — it doesn't
    generalize to the `claude_code` path (see below).
  - **`claude_code` concurrency — explicitly left open, not guessed at.**
    Unlike Ollama, the `claude` CLI's compute runs on Anthropic's
    infrastructure, not this box — there's no equivalent hardware reason to
    serialise it to 1. The real limiting factor, if any, would be Claude
    subscription rate/usage limits, which haven't been measured. No cap is
    set here; picking one now without evidence would repeat exactly the
    mistake R0.3 was written to avoid ("watch memory" → an actual number,
    not a guess).
  - **Network egress — no change.** Loopback traffic to Ollama needs
    nothing. Outbound HTTPS to Anthropic (for the `claude` CLI) already
    works from this exact machine today, since the Python pipeline makes
    that same call right now. No firewall/security-group work, because
    nothing is deployed.
  - **Timeout, signal handling, and output draining — inherited from R0.1,
    not re-solved here.** Process-group SIGTERM→grace→SIGKILL and full
    stdout/stderr draining are already `Pipeline::Subprocess.run`'s job
    (R0.1, already shipped); R1's `claude` CLI call is just another caller
    of that primitive. Python's `claude_code_agent.py` enforces its own
    1200s `subprocess.run(timeout=...)` today — in Ruby, pick one timeout
    value at the call site (likely 1200s, to match current behavior)
    rather than building a second timeout mechanism. Picking the exact
    number is a code decision for R1's build, not settled here.
  - **Known gap in R0.1, surfaced by this review — not fixed here.**
    `Pipeline::Subprocess.run`'s reader threads buffer the entire
    stdout/stderr stream in memory with no size cap. An unexpectedly large
    translation response could grow that buffer without bound. This is a
    follow-up to R0.1's primitive itself (affects every caller, not just
    R1), filed here rather than fixed as a side effect of R1's design pass.
  - **Observability — structured fields, explicit error buckets.** A
    backend-seam call should log backend name (`local`/`claude_code`),
    model, budget ceiling, and R0.1's existing `Result` fields
    (`command_name`, `duration`, `exit_code`/`status`) — never raw
    `system_prompt`/`user_message`/stdout content, matching R0.1's existing
    logging constraint. Errors should be classified into the same three
    buckets as the failure taxonomy above (infra / usage / content) so logs
    are triageable by category rather than a flat pile of stderr strings.
- **Acceptance criteria:**
  - Every env var R1's eventual Ruby code reads is named identically to its
    Python counterpart — no new Ruby-only var invented for a concept Python
    already names — and read through one validated point, not scattered
    `ENV.fetch` calls.
  - `CLAUDE_BIN` resolves to an absolute path before spawn; the child's env
    never includes `PATH`.
  - The `claude` CLI subprocess's env is a documented allowlist (`HOME`,
    `MCP_CONNECTION_NONBLOCKING`) built additively from `{}`, explicitly
    excluding `RAILS_MASTER_KEY`, `DATABASE_URL`, `ANTHROPIC_API_KEY`, and
    any `*_SECRET`/`*_KEY`/`*_TOKEN` — written down before any code forwards
    `ENV.to_h` into this particular subprocess, and R0.1's existing
    full-`ENV`-forwarding call site is named as required cleanup.
  - The `claude` CLI is invoked via argv array, never a shell string.
  - stdin's role (prompt delivery, not closed) is stated correctly, matched
    against the actual Python implementation rather than assumed.
  - A failure taxonomy (6 categories) exists for later error-handling code
    to map onto.
  - `claude_code` concurrency has no invented cap — stated as an open,
    unmeasured question, distinct from Ollama's local-hardware constraint.
  - OAuth credential provisioning for a deployed `claude` CLI is named as an
    explicitly open, unscheduled question — not silently assumed solved,
    not solved prematurely either.
  - No firewall, Kamal, or deploy-config changes are made — R1 runs against
    the existing local systemd process, same as every other job type today.
  - No Ruby implementation code is written as part of this section — that's
    a separate, later pass.

## R2 — `bible_lookup` in-process design

**Status: designed (2026-07-24), revised same day after review. No Ruby
code written yet.** Same design-only treatment as R1, at the user's
request. This section also corrects a real gap in the original roadmap's
framing of R2 — see the dependency note below before treating R2 as
buildable in isolation.

- **Goal:** Design the Ruby shape of the `bible_lookup` skill so it calls
  `BibleSearchService` directly (in-process) instead of the current
  Python-side loopback HTTP round trip, without designing the general
  skill-invocation mechanism that will call it — that belongs to R1 (the
  "local" backend's tool-calling loop) and R3 (the MCP bridge), not here.
- **Dependency finding — the original roadmap's "worth doing even
  standalone" claim needs a caveat.** Today, both Python backends already
  reach `bible_lookup.py#execute()` in-process — `src/agent.py`'s own
  agentic loop (the "local" backend) calls `skill.execute(tool_args)`
  directly (`src/agent.py:195-198`), and the "claude_code" backend reaches
  it via the MCP bridge subprocess. `execute()` itself is what does the
  HTTP round trip, in both cases. So the HTTP hop this section removes is
  inside the skill's own implementation, not something bolted on
  separately per backend — good news for scoping, since porting the skill
  fixes it for both backends at once. The caveat: nothing today can call
  the *ported Ruby* skill class until either R1 ports `src/agent.py`'s tool
  loop (for `"local"`) or R3 ports the MCP bridge (for `"claude_code"`).
  R2's skill class can be **built and spec'd in isolation** right now
  (call `.execute` directly in RSpec, no LLM involved) — that much of
  "standalone" holds. It cannot be **exercised end-to-end by either
  backend** until R1 or R3 also lands. Both should be true in this
  document rather than only the first.
- **Design:**
  - **Shared `Skill` interface — a joint dependency of R1, R2, and R3, not
    invented separately by whichever phase gets built first.** Python's
    `src/skills/base.py::Skill` defines the contract every skill satisfies:
    a `tool_definition`, `execute(tool_args) -> String`, and a `name`
    convenience accessor. Ruby needs the equivalent shape so R1's "local"
    tool loop and R3's MCP bridge can both call any skill identically.
    **The schema belongs to no single provider — described generically as
    a tool schema (name + description + JSON-schema parameters), adapted
    per provider, not owned by one.** Checked against
    `skill_bridge.py:52-61`: the bridge doesn't forward `tool_definition`
    to MCP verbatim today — it already extracts
    `tool_definition["function"]["description"]` and `["parameters"]` to
    build an MCP `types.Tool(inputSchema=...)`. So the bridge already
    treats the schema as an intermediate format it adapts, not a
    provider-owned pass-through; this section's wording now matches that
    rather than calling it "OpenAI-format," which implied the interface
    belonged to one provider when the code already disagrees. This
    interface is small and stable enough that R2 can assume its rough
    shape without waiting for R1 to formally settle it — but whoever
    builds R1's tool loop first should treat that as the moment this
    interface actually gets fixed, and this section's design should be
    revisited if it lands differently.
  - **`bridge_spec()`-equivalent — explicitly not R2's problem.** Python's
    `bridge_spec()` exists to reconstruct a skill instance inside a fresh
    subprocess (the MCP bridge) that doesn't share memory with the caller.
    Ruby's MCP bridge (R3) is very likely still a separate OS process too —
    forked by the `claude` CLI itself, per the proposed architecture
    diagram earlier in this doc — so the same reconstruction problem
    (how does a freshly-spawned bridge process get a `BibleLookup` instance
    scoped to the right novel, and does that process even have the Rails
    environment loaded to reach `BibleSearchService`?) still needs solving.
    That's named here as an R3 dependency to watch for, not solved in this
    section — R2 only designs the skill class itself, assuming it runs
    somewhere the Rails environment is already loaded.
  - **Two HTTP hops removed, not one.** Today's Python skill makes two
    separate round trips: `GET /novels/find_by_directory?directory_name=`
    to resolve a novel ID (`bible_lookup.py:115-132`, memoized after first
    call), then `GET /novels/:id/bible/search?q=&categories[]=&limit=`
    (`bible_lookup.py:94-105`, calling `BibleSearchController#show` →
    `BibleSearchService`). In Ruby, novel resolution becomes a single
    `Novel.find_by!(directory_name:)` — no HTTP, not even to Rails' own
    routes. The search call becomes `BibleSearchService.new(scope: novel,
    query:, categories:, limit: 5).call` directly, skipping
    `BibleSearchController` entirely (that controller stays — it's still
    the UI's own bible-search endpoint, untouched by this). **The skill
    depends only on `BibleSearchService`'s public API** (`.new(...).call`)
    — never its private scoring/merge/formatting internals — so
    `BibleSearchService` stays free to refactor those without touching R2.
  - **Instance lifetime, thread safety, and the `find_by!` contract.**
    Checked against `translate.py:221`/`translate_batch.py:221`: today's
    skill is instantiated fresh per call site
    (`BibleLookupSkill(novel_dir.name, HAWK_RAILS_URL)`), never a shared
    singleton — the Ruby port keeps this shape. Novel resolution is
    memoized on **that instance** (an `@novel` ivar, mirroring today's
    `@novel_id`), not a class variable or any form of global/process-wide
    cache; the instance is discarded once its job finishes, so nothing
    persists or leaks across jobs. Because each job/call site owns its own
    instance, the skill is never shared between concurrent jobs — stated
    explicitly here rather than left to infer, since a future reader
    reaching for `Rails.cache` or a class-level `@@novel` to "avoid
    re-resolving" would silently reintroduce cross-job leakage. `Novel.find_by!`
    raising `ActiveRecord::RecordNotFound` on a missing novel must be
    rescued **at the skill's call site**, converting it into a
    `"[bible_lookup error: ...]"`-shaped return — otherwise the bang
    finder contradicts the "never raise" contract below. This isn't a new
    pattern: `BibleSearchController#set_novel` already does exactly this
    (`Novel.find` + `rescue ActiveRecord::RecordNotFound`) for the same
    reason, just returning a string instead of a 404.
  - **Result formatting ports verbatim, and belongs to R2, not R4.** One
    formatter per category (`_format_record`'s branches for
    `BibleCharacter`/`BibleLocation`/`BibleTerminology`/
    `BibleCulturalPhrase`/`BibleStoryEntry`, `bible_lookup.py:149-204`,
    five today) is this skill's own output shaping, not the
    prompt-construction/response-parsing logic R4–R6 are scoped around.
    Framed as "one formatter per category" rather than "five branches" so
    a future extraction into one class per category (a
    `CharacterFormatter`/`LocationFormatter`/... registry, should the
    branch ever get unwieldy) stays available without this document having
    described the current behavior as an inherent five-way `case`. Not
    proposed now — the current single method with five branches is
    perfectly reasonable at this size. **Formatter output is part of the
    model-facing interface, not incidental presentation** — it's the exact
    text the translation prompt sees when the model calls this tool, so a
    future formatting "cleanup" is a translation-quality-affecting change
    and should be reviewed with the same care as R4–R6's prompt changes,
    not treated as free-standing refactoring.
  - **Error contract preserved: never raise, always return a string — and
    the string is the compatibility layer, not an implementation
    afterthought.** Python's `execute()` catches broadly and returns
    `"[bible_lookup error: ...]"`-shaped strings rather than raising — a
    tool result the model can read and react to, not an application
    exception. The Ruby port keeps this: a resolution failure (novel not
    found, via the rescued `ActiveRecord::RecordNotFound` above) or a
    search failure becomes a returned error string, not a raised error
    that would abort the surrounding job/call. Internal Ruby data (e.g. an
    intermediate struct built while formatting) may exist freely as
    implementation detail, but `execute`'s public return type stays a
    formatted `String` — not a `Hash` — for compatibility with whatever
    calls it (R1's tool loop, R3's bridge). Stated explicitly so "Ruby
    should return structured data" doesn't quietly break that contract
    later.
  - **Category enum stays exactly the five existing types.** No new
    category, no renaming — `BibleCharacter`, `BibleLocation`,
    `BibleTerminology`, `BibleCulturalPhrase`, `BibleStoryEntry`, matching
    both `_CATEGORY_LABELS` (Python) and `NAME_ENTRY_CONFIG`
    (`BibleSearchService`, Ruby) today.
  - **`HAWK_RAILS_URL` becomes dead code for this skill, not deleted
    project-wide.** It's still referenced by `config.py` today for this one
    purpose; once `bible_lookup` no longer needs it, whether the var itself
    gets removed is a Python-cleanup decision for R7 (deleting the Python
    layer entirely), not something to touch now.
  - **Testing strategy — three layers, matching this section's own
    dependency graph.** Not written now (no code this pass), but named so
    R2's eventual spec suite has a shape to aim for rather than one flat
    pile of specs: **unit** (`BibleSearchService` mocked/stubbed — tests
    the skill's own argument-building, novel resolution, error handling,
    and formatting in isolation); **integration** (real database, real
    `BibleSearchService` call, real formatter output — no LLM involved,
    same as the "buildable and spec'd in isolation" claim above);
    **end-to-end** (an actual tool invocation through R1's `"local"` loop
    or R3's bridge, reaching a real LLM) — only possible once one of those
    two lands, same dependency this section already names.
- **Acceptance criteria:**
  - The Ruby `bible_lookup` skill's design (tool schema, `execute`-shaped
    method) is specified against the shared `Skill` interface R1/R3 will
    also use — described as a provider-neutral tool schema, not an
    OpenAI-owned one — not a bespoke shape invented only for this skill.
  - Both HTTP hops (`find_by_directory`, `bible/search`) are replaced by
    direct Ruby calls (`Novel.find_by!`, `BibleSearchService.new(...).call`)
    — zero HTTP requests, including to the app's own routes — touching only
    `BibleSearchService`'s public API.
  - Novel-resolution memoization is instance-scoped (`@novel`), never a
    class variable or global cache; the skill instance is constructed fresh
    per job/call site and is never shared across concurrent jobs.
  - `Novel.find_by!`'s `ActiveRecord::RecordNotFound` is rescued at the
    skill's call site and converted into the same error-string contract as
    every other failure mode — never left to propagate and abort the job.
  - The five category formatters are ported as part of this skill, not
    deferred to R4; their output is documented as part of the model-facing
    interface, not free-standing presentation.
  - The error contract (return a string, never raise) is preserved, and
    `execute`'s public return type is a `String`, not a `Hash`, regardless
    of what internal Ruby data structures exist behind it.
  - A three-layer test strategy (unit / integration / end-to-end) is named
    for whoever writes R2's spec suite.
  - This document states plainly that R2's skill class is buildable and
    testable standalone, but not usable end-to-end by either backend until
    R1 (`"local"` tool loop) or R3 (MCP bridge) also exists — correcting
    the original roadmap's unqualified "worth doing even standalone" claim.
  - The MCP-bridge subprocess's ability to reach `BibleSearchService` at
    all (Rails environment loaded in a forked bridge process) is named as
    an open R3 dependency, not assumed solved by this section.
  - No Ruby implementation code is written as part of this section — that's
    a separate, later pass.

## R3 — Skill bridge onto the `mcp` gem

**Status: designed (2026-07-24), no Ruby code written yet.** Design only, at
the user's request (confirmed via clarifying question, same as R2). This
section required more real-code verification than R1 or R2 got right on
first pass — the actual installed `mcp` gem's API doesn't match either this
document's own prior assumptions or the original artifact's, on two separate
points. Both are corrected below against the gem's real source, not guessed.

- **Goal:** Design how the Ruby port of the MCP skill bridge — the subprocess
  the `claude` CLI itself spawns per translation call to expose skills as MCP
  tools — is structured on top of the official `mcp` gem, so that R2's
  `bible_lookup` design has a concrete calling convention to plug into. Only
  `bible_lookup` is wired here; `web_search` (also named in the original
  roadmap's R3 scope) is out of scope for this pass, same reasoning as R2
  scoping out everything but `bible_lookup` — port it separately later.
- **Finding — the `mcp` gem is already in this app, just not for this
  reason.** `Gemfile.lock` already resolves `mcp (0.8.0)` — checked via
  `gem specification mcp -v 0.8.0`, confirmed genuinely
  `https://github.com/modelcontextprotocol/ruby-sdk`, "The official Ruby SDK
  for Model Context Protocol servers and clients." It's pulled in
  transitively by `rubocop (~> 0.6)`, in the `:development, :test` group
  (`Gemfile:39`) — Rubocop 1.85 ships its own MCP server for editor
  integration, unrelated to this refactor. Two concrete consequences for
  R3's build, not just trivia:
  - **The version this document should target is 0.8.0, not the "v0.25.0"
    the original artifact cited.** That number was wrong (or stale) the
    moment it was written — corrected here against the actual lockfile
    rather than repeated.
  - **R3 needs `gem "mcp"` added to the main Gemfile group**, since the
    bridge is production code, not a dev tool — the current transitive
    inclusion doesn't reach a production boot. Whatever version gets pinned
    must stay compatible with rubocop's `~> 0.6` constraint (0.8.0 already
    satisfies both `~> 0.6` and a hypothetical direct `~> 0.8`) unless
    rubocop's own pin is bumped at the same time — a real Bundler-resolution
    constraint to check at build time, not assumed away.
- **Finding — `MCP::Tool` is class-based; R2's `Skill` design is
  instance-based. These don't map onto each other directly.** Read
  `lib/mcp/tool.rb`, `lib/mcp/server.rb`, and
  `lib/mcp/server/transports/stdio_transport.rb` directly (installed gem,
  not docs) to check this rather than assume the SDK mirrors Python's shape:
  - `MCP::Tool` subclasses declare `tool_name`, `description`, `input_schema`
    as **class-level** DSL calls, and `def self.call(*args, server_context:
    nil)` is a **class method** — there is no per-tool instance at all.
  - Per-invocation state doesn't live on the tool. `MCP::Server.new(tools:,
    server_context:, ...)` takes **one** `server_context` object for the
    server's whole lifetime; `call_tool_with_args` (`server.rb:491-499`)
    calls `tool.call(**args, server_context: server_context)` for every tool,
    every call — the same object, every time.
  - Python's `Skill` is the opposite: an instantiated object
    (`BibleLookupSkill.new(novel_dir_name, rails_url)`), with `bridge_spec()`
    existing specifically to reconstruct that per-instance state in a fresh
    process. R2's design (instance-scoped `@novel` memoization, "fresh
    instance per call site") was written correctly for Python's model — but
    a literal line-for-line port of that shape onto `MCP::Tool` doesn't work,
    because `MCP::Tool.call` has no instance to memoize onto.
  - **Resolution, proposed here rather than left as a contradiction:** keep
    R2's skill class exactly as designed (instance-based, `BibleLookup.new(
    novel:).execute(tool_args)`-shaped, callable directly by R1's `"local"`
    tool loop) and add a **thin `MCP::Tool` adapter subclass** whose
    `self.call(**args, server_context:)` reads the novel from
    `server_context`, constructs a `BibleLookup` instance from it, and calls
    `.execute`. The adapter is R3's code, not a change to R2's design — R2's
    skill class stays the single source of truth for the actual lookup
    logic; the adapter only translates between the gem's class-based calling
    convention and R2's instance-based one.
  - This resolves R2's flagged open question — "does a freshly-spawned
    bridge process have what it needs to reach `BibleSearchService`" — more
    simply than Python's model needed: since the bridge subprocess is
    spawned fresh per translation call (see below) and `server_context` is
    built fresh at that same spawn, there is exactly one `server_context`
    object per job, never shared or reused — the same "never shared across
    concurrent jobs" property R2 stated for its `@novel` ivar falls out of
    this for free, rather than needing separate enforcement.
  - **`server_context`'s shape, stated explicitly rather than left
    conceptual:** an immutable value object, built once per bridge-process
    spawn, containing only the minimal per-call context a tool actually
    needs (a novel id, for `bible_lookup` — nothing else today) — no mutable
    caches, no `attr_writer`s, nothing appended to it over the process's
    lifetime. `Data.define` (available since Ruby 3.2, this app targets
    3.4.2) is the natural shape — a frozen value object rather than a
    plain mutable `Hash`, matching R0.1's existing precedent of using a
    proper struct (`Pipeline::Subprocess::Result`) for exactly this kind of
    "small, fixed, done-once" data rather than a hash. Stated as a
    constraint now specifically so a later "just add one more field to
    server_context" doesn't quietly turn it into an unbounded dumping
    ground.
  - **The adapter carries no business logic — stated as a constraint, not
    just a description of today's code.** `call` does exactly four things:
    read `server_context`, construct a `BibleLookup` instance from it,
    delegate to `.execute`, wrap the string result in a
    `Tool::Response`. No formatting, no argument validation, no
    error-message shaping belongs in the adapter — that's what R2's skill
    class already owns (formatting) and what the gem's own `call_tool`
    already does before the adapter ever runs (argument validation against
    `input_schema`, on by default —
    `MCP::Configuration#validate_tool_call_arguments` defaults to `true`,
    checked in `configuration.rb:13`). Written down now because "just add a
    little validation/formatting here, it's convenient" is exactly the kind
    of thing that accretes into an adapter unnoticed over time, six months
    from now, by someone who wasn't in this design conversation.
  - **Why the adapter exists at all, so a future reader doesn't have to
    reverse-engineer it:** the adapter exists solely because the `mcp` gem
    models tools as class-level objects, while this app's skill classes
    stay instance-based on purpose — for consistency with R1's `"local"`
    tool loop (which calls skill instances directly, no adapter involved)
    and for easier testing (a skill instance can be built and exercised in
    isolation without any MCP machinery at all, as R2 already established).
    `BibleLookup` does not, and should not, inherit from `MCP::Tool`.
  - **Anti-pattern, named explicitly:** no memoizing a skill instance across
    calls in the adapter — no class-level `@@instance`, no
    memoized `@cached_lookup`. The bridge process's whole lifecycle is one
    translation call; a `BibleLookup` instance built fresh inside `call`
    and discarded when `call` returns is the entire point, not an
    inefficiency to optimize away. The lifecycle diagram below exists
    partly to make this concrete.
  - **Bridge process lifecycle, drawn once so "why nothing needs caching
    beyond one job" doesn't have to be inferred from prose:**
    ```mermaid
    flowchart TB
        A["claude CLI spawns bridge subprocess\n(per translation call)"]
        B["bridge script boots enough Rails\nto reach ActiveRecord/BibleSearchService"]
        C["server_context built once\n(e.g. novel id)"]
        D["MCP::Server.new(tools:, server_context:)\nStdioTransport#open"]
        E["tool call arrives over stdio"]
        F["adapter: BibleLookup.new(...) → execute → Tool::Response"]
        G["response written to stdout"]
        H["claude CLI call finishes → bridge process exits"]
        A --> B --> C --> D --> E --> F --> G --> E
        G --> H
    ```
    `E → F → G` can repeat any number of times within one bridge process
    (one `claude` call can invoke a tool more than once) — what never
    repeats is `A`–`C`: the process, and everything built at its start, is
    scoped to exactly one translation call and then discarded.
- **Finding — unregistered tool names fail before any adapter code runs;
  verified against the gem, not assumed.** Checked `server.rb`'s
  `call_tool`: `tool = tools[tool_name]; unless tool ... raise
  RequestHandlerError.new(..., error_type: :invalid_params)`. That exception
  propagates to `process_request` in `json_rpc_handler.rb`, which converts
  it into a genuine JSON-RPC error response (`code: -32602`, `INVALID_PARAMS`)
  — a protocol-level failure, not a tool result at all. This is a real
  behavior difference from Python's bridge, not just a stylistic one:
  `skill_bridge.py:65-67` handles an unknown tool name itself, inside
  `call_tool()`, returning an ordinary
  `[TextContent(text: f"[error: unknown tool {name!r}]")]` — a
  successful-looking tool response with the error embedded as text, the
  same shape as every other error in that file. The Ruby `mcp` gem instead
  enforces this at its own dispatch layer, before any registered tool code
  (including this design's adapter) ever executes — the trust boundary
  ("only these exact tool classes can run") is the SDK's own guarantee, not
  something R3 needs to build or test for itself. Only the tool classes
  actually passed to `MCP::Server.new(tools: [...])` are ever reachable;
  nothing else needs a written check.
- **Finding — Python's dynamic skill-loading mechanism doesn't need a Ruby
  equivalent, and this removes a security concern the original artifact
  flagged rather than just porting it.** `skill_bridge.py`'s `_load_skills()`
  (`importlib.import_module(spec["module"])` + `getattr` + `skill_cls(**spec
  ["kwargs"])`) exists because Python needs to reconstruct arbitrary skill
  *instances* from a JSON spec passed via `HAWK_SKILLS_SPEC`, since the
  bridge subprocess shares no memory with its caller. The original artifact's
  design-review section flagged this as a "sharp edge" that "same shape of
  risk applies to Ruby's `Object.const_get` if R3 ports this literally."
  Verified against the finding above: it doesn't need to be ported literally,
  because Ruby's tools carry no constructor state to reconstruct — the
  bridge script can `require` and reference actual `MCP::Tool` subclasses
  directly (e.g. `Pipeline::Skills::BibleLookupTool`), with no runtime
  string-to-class resolution at all. What still needs to cross the
  subprocess-spawn boundary is much smaller than Python's `{module, class,
  kwargs}` spec: which known tool classes to register (a short list of
  names, matched against a small, statically-known set the bridge script
  already requires) and whatever minimal per-call context builds
  `server_context` (e.g. a novel id). No dynamic `const_get` on
  caller-influenced input is needed — the risk the artifact flagged doesn't
  carry over, rather than being mitigated.
- **stdin/stdout discipline — same constraint as Python, verified against
  the actual transport.** `StdioTransport#open` (`stdio_transport.rb`) loops
  `$stdin.gets`, and `send_response` writes JSON straight to `$stdout`.
  Exactly like `skill_bridge.py:74-79`, nothing inside a tool's `call` may
  write to `$stdout` — a stray `puts` would corrupt the JSON-RPC stream the
  same way it would in Python. Python's bridge redirects `sys.stdout` to
  `sys.stderr` around `skill.execute()` for exactly this reason; the Ruby
  bridge script needs the equivalent redirect (`$stdout = $stderr`, restored
  after) around every tool call, stated here as a requirement for R3's build.
- **Finding — MCP has a native error channel Python's bridge never uses;
  decide this deliberately, don't drift into it.** `MCP::Tool::Response`
  (`tool/response.rb`) supports `error: true`, surfaced to the client as
  `isError` — a real protocol-level failure signal. Checked
  `skill_bridge.py:63-81` directly: it never sets this. Every call —
  including the unknown-tool case and whatever `"[bible_lookup error: ...]"`
  string `execute()` returns — comes back as ordinary
  `[TextContent(text: result)]`, `isError` absent. **Recommendation: preserve
  this exactly** — the adapter's `call` should always return
  `MCP::Tool::Response.new([{type: "text", text: result}])` with `error:`
  left at its `false` default, keeping R2's "never raise, return a string"
  contract intact all the way through the protocol rather than starting to
  use a channel the current system doesn't. Named explicitly so a future
  "hey, shouldn't failures set `isError`?" isn't a silent, undiscussed
  behavior change against existing (working) semantics.
- **Bridge process spawn cost — a real open question, not solved here.**
  Checked `claude_code_agent.py:161-177` (`_mcp_config_json`): the bridge is
  spawned fresh **per translation call**, `command: sys.executable, args:
  [skill_bridge.py]` — a bare Python interpreter loading one small script,
  cheap. A Ruby bridge process spawned the same way needs enough of Rails
  loaded to reach `ActiveRecord`/`BibleSearchService` — a `config/
  environment.rb` boot (DB connection pool, full app initialization) is a
  meaningfully heavier per-call cost than Python's bare interpreter start.
  Whether that's a full Rails boot, a narrower partial load, or something
  else is a real engineering question for R3's actual build — flagged here,
  not guessed at, same discipline as R1's declined concurrency-cap and R0.3's
  "measure before deciding."
- **Bridge command path — one resolution policy for every subprocess this
  migration introduces, not a per-phase rule that happens to look similar
  twice.** Stated as an invariant rather than "R3 matches R1": all
  subprocesses this refactor introduces — R1's `claude` CLI invocation, R3's
  bridge script invocation — resolve their executable to an absolute path
  once, before spawn, and never hand a bare/PATH-searched command to
  `Process.spawn`. Whatever spawns the Ruby bridge script (the
  `command`/`args` values built into `--mcp-config`, replacing
  `_mcp_config_json`) follows that same policy — it isn't R3 borrowing a
  detail from R1, it's one architectural rule the whole migration shares.
- **Testing strategy — adapted from R2's three layers, not reinvented.**
  **Unit**: the `MCP::Tool` adapter's `call` tested directly as a class
  method, `server_context:` stubbed, no real `MCP::Server`/transport
  involved. **Integration**: a real `MCP::Server` wired to the real adapter
  and a real `StdioTransport` (or the server's `handle`/`handle_json` called
  directly, bypassing stdio) against a real database — proves the JSON-RPC
  shape and `BibleSearchService` call both work, no LLM involved.
  **End-to-end**: an actual `claude` CLI call, via R1's backend, actually
  spawning the bridge subprocess and reaching a real LLM — only meaningful
  once R1's Ruby backend-seam code exists to make that call at all.
- **`web_search` — explicitly not designed here.** The original roadmap
  scoped `web_search` into R3 alongside the bridge mechanism itself. This
  section designs the bridge mechanism and wires `bible_lookup` (R2's only
  designed skill) through it; porting `web_search`'s own Tavily-calling logic
  is separate, later work, same way R2 scoped out everything but
  `bible_lookup`.
- **Why this shape scales without redesign, worth naming as a sanity check
  on the design rather than assuming it:** every future skill (`web_search`,
  or novel ones like a glossary or character lookup) becomes one instance-
  based skill class (R2's shape) plus one thin `MCP::Tool` adapter (R3's
  shape) — the bridge script itself, `MCP::Server`, and `server_context`'s
  contract don't change per skill added. That each new skill is
  "skill class + adapter," not "another special case inside the bridge," is
  a sign this design is sitting at the right level rather than one that'll
  need revisiting at the second or third skill.
- **Acceptance criteria:**
  - `mcp` (0.8.0, verified against the actual `Gemfile.lock`, not the
    original artifact's stale "v0.25.0") is added to the Gemfile's main
    group, with its version kept compatible with rubocop's existing
    `~> 0.6` constraint rather than causing a Bundler resolution conflict.
  - The bridge's tool classes are `MCP::Tool` subclasses (class-level
    `call(*args, server_context:)`), not a literal port of Python's
    instance-based `Skill` — R2's skill class is reused via a thin adapter,
    not duplicated or redesigned.
  - Per-invocation state (e.g. which novel) flows through `MCP::Server`'s
    single `server_context` object, built fresh per bridge-subprocess spawn
    — never a class-level/global mutable value shared across calls.
  - `server_context` is an immutable value object (e.g. `Data.define`)
    containing only the minimal per-call fields a tool needs, never a
    mutable cache or a dumping ground that grows opportunistically as new
    fields seem convenient.
  - The adapter contains no business logic — no formatting, no argument
    validation, no error-message shaping — beyond reading `server_context`,
    constructing a skill instance, delegating to `execute`, and wrapping the
    result. No skill instance is memoized across calls (no `@@instance`, no
    memoized ivar) — a fresh instance per call is the design, not something
    to optimize away later.
  - Requests naming a tool outside the exact set passed to
    `MCP::Server.new(tools: [...])` fail at the SDK's own dispatch layer (a
    JSON-RPC `INVALID_PARAMS` error) before any adapter code runs — verified
    against `server.rb`/`json_rpc_handler.rb`, not assumed.
  - No dynamic string-to-class resolution (`Object.const_get` on
    caller-influenced input) is introduced — tool classes are `require`d and
    referenced directly, since Ruby's tools carry no per-instance
    constructor state to reconstruct the way Python's `bridge_spec()` needs.
  - The bridge script never writes to `$stdout` from within a tool call —
    stated as a requirement, mirroring Python's existing
    stdout-to-stderr redirect.
  - Tool-execution failures continue to be reported as text content (the
    existing `"[bible_lookup error: ...]"`-shaped string), not MCP's native
    `isError` flag — a deliberate parity decision, stated rather than
    silently drifted into.
  - The bridge subprocess's Rails-boot cost is named as an open engineering
    question for R3's build, not assumed solved or guessed at with a number.
  - Whatever spawns the bridge process resolves its command to an absolute
    path, matching R1's `CLAUDE_BIN` resolution discipline.
  - `web_search` is explicitly out of scope for this section.
  - No Ruby implementation code is written as part of this section — that's
    a separate, later pass.

---

**R0 is fully built (R0.3 skipped by decision). R1's infra, R2's
`bible_lookup` design, and R3's skill-bridge design are all fully designed,
with no Ruby implementation code written for any of them yet.** The next
build step, whenever picked up, is writing actual Ruby code — R1's
backend-seam adapters, R2's `bible_lookup` skill class, and R3's `MCP::Tool`
adapter + bridge script, most naturally in that order since R3's adapter
depends on R2's skill class existing and R1's backend needs to exist before
either skill can be exercised end-to-end. R4–R7 remain at summary level in
the linked artifact.
