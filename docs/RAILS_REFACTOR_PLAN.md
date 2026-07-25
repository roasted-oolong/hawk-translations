# Full-Rails Refactor Plan

Retiring the Python translation pipeline (`src/` + 9 root scripts, ~5,600 LOC)
in favor of an all-Ruby stack. Not a roadmap item — discretionary architecture
work.

**Status as of 2026-07-25: R0.5, R0.1, and R0.4 done. R0.2's config is
written but not deployed. R0.3 is explicitly skipped — see below. R1
(backend-seam infra: `TranslationConfig`, `Pipeline::ClaudeCode`), R2
(`Pipeline::Skills::BibleLookup`, in-process), R3 (the skill bridge
onto the official `mcp` gem: `Pipeline::Mcp::ServerContext`,
`Pipeline::Mcp::BibleLookupTool`, `bin/mcp_skill_bridge`), and now R6
(`preread`/`bible_build` orchestration) are all built, tested, and (R1–R3)
committed to `main` — R6's commit is still pending, see below. R4
(`translate_batch` orchestration — the first phase that actually wires
R1–R3 together end-to-end) is designed, with no Ruby code written yet —
see the R1–R4 sections below for what exists, what's designed-only, and
what's still open (R4's design surfaced a real open question about the
`claude` CLI's own MCP-server-spawn env behavior, needing a smoke test
before its build starts). R5 (`post_translation_review` +
`voice_calibration` orchestration) is also designed, same discipline as
R4 — see the R5 section below.**
All five R0 milestones, plus R1, R2, R3, and now R6, have reviewed
Goal/Design/Acceptance-criteria sections and real Ruby implementations
with passing specs. R4 and R5 have the same Goal/Design/Acceptance-criteria
treatment but no implementation yet. The formatter/OCR slice of the original
R6 summary and R7 are still at the summary level in the artifact linked
below; they have not been given the same detailed treatment.

**R6 build, 2026-07-25, same session as this doc's R4/R5/R6 design passes:**
`Pipeline::Ruby::Preread` and `Pipeline::Ruby::BibleBuild` are no longer
`NotImplementedError` stubs. Built, in dependency order: `Pipeline::PromptUtils`,
`Pipeline::BibleUtils`, `Pipeline::BibleFileEditor` (the shared locking/
atomic-write primitive R5's `BibleReviewWriter` will also consume once R5 is
built — built now because R6 needs it, per the design doc's shared-primitive
note below), `Pipeline::Ruby::PrereadRunner::ChapterDiscovery`,
`::PromptBuilder` (system-prompt output verified byte-for-byte against a live
`python3` invocation of the real `src/preread/prompt_builder.py`, not
hand-transcribed — see `spec/fixtures/preread/`), `::ResponseParser` (adds
the fail-closed "zero section markers at all" distinction the design doc
calls for, which Python's own parser doesn't actually implement — its
"missing sections" warning was dead code), `Pipeline::PrereadBibleWriter`,
and `Pipeline::Ruby::PrereadRunner` itself (the shared batch-loop
orchestrator; `Pipeline::Ruby::Preread`/`BibleBuild` are now thin callers
supplying their own discovery predicate and batch size — 2 for preread, 5
for bible_build, matching today's live Python asymmetry). One deliberate
scope trim from the design: Python's `time.sleep(1)` between batches
("brief pause... to be kind to the API") wasn't ported — it's not
correctness-critical and isn't named in the design's acceptance criteria.
Full spec suite run to confirm no regressions beyond the known-red baseline
(see below). Not yet committed — see the project's own git history for
whether this has landed by the time you're reading this.

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
config itself. With R0.3 skipped, R0 is otherwise closed. R1, R2, and R3
are built (see the R1, R2, and R3 sections below for what exists). R4 is
now designed (see the R4 section below) but not built — the next build
step is writing `Pipeline::Ruby::TranslateBatch` against that design,
starting with the smoke test R4 flags (a real `claude -p` call through a
real `--mcp-config`, to settle whether the bridge subprocess actually
reaches Postgres under the recommended env allowlist) before the rest of
the orchestration code. R5 (see the R5 section below) is also designed but
not built — its build has no R4-shaped smoke-test blocker (neither of its
two job types uses an `--mcp-config`/bridge at all) so it can be built
independently of, and in either order relative to, R4. R6 (see the R6
section below — `preread`/`bible_build` only; the formatter/OCR slice of
the original summary remains unscheduled) is also designed but not built;
its orchestrator half is independent of R4/R5 too, but its writer half
shares a new primitive, `Pipeline::BibleFileEditor`, with R5's amended
`BibleReviewWriter` — whichever of R5/R6 is built first builds that
primitive once. The formatter/OCR slice and R7 remain unscheduled.

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
- **R4** — port `translate_batch`'s orchestration (reference-file loading,
  prompt assembly, `mcp_config` construction, sequential
  `Pipeline::ClaudeCode` calls) — the first phase to actually wire R1–R3
  together. Designed (see the R4 section below); not yet built.
- **R5** — port `post_translation_review` (`run_review.py`) and
  `voice_calibration` (`calibrate-voice.py`) orchestration — single-call
  prompt-build/parse/apply flows, no `--mcp-config`/bridge involved for
  either. Designed (see the R5 section below); not yet built.
- **R6** — port `preread`/`bible_build`'s shared batch-loop orchestration
  (`src/preread/*`) — the slice of the original "R6" summary (which also
  named the formatter and OCR) that fits directly into the existing
  `PipelineDispatcher`/`PIPELINE_IMPL_*` machinery. Designed (see the R6
  section below); not yet built. The formatter (`clean_chapter.py`) and OCR
  (`ocr_chapter.py`) remain unscheduled and summary-level — both are
  triggered outside `PipelineDispatcher` entirely (plain `ActiveJob`s on
  chapter upload, no `PIPELINE_IMPL_*` toggle today), a structurally
  different migration than R6's.
- **R7** — delete the Python layer (`venv/`, `requirements.txt`, Dockerfile
  stage), revisit the now-obsolete "`ANTHROPIC_API_KEY` stays in `.env`"
  decision.

Current recommendation: land R0 → R1–R3 now (done); R4, R5, and R6 are
designed and ready to build, in any order (R5's and R6's writers share
`Pipeline::BibleFileEditor`, so whichever lands first builds it); the
formatter/OCR slice of the original R6 and R7 remain unscheduled.

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

**Status: built 2026-07-24 — `TranslationConfig` (`app/services/translation_config.rb`)
and `Pipeline::ClaudeCode` (`app/services/pipeline/claude_code.rb`), both
with passing specs.** Building this surfaced one real gap in R0.1's
`Pipeline::Subprocess` beyond what the design pass anticipated:
`Process.spawn` merges the given `env:` hash into a copy of the *parent's*
full environment by default rather than replacing it, which would have
silently defeated the whole point of this section's allowlist. Fixed by
adding `unsetenv_others: true` to `Pipeline::Subprocess`'s spawn call —
behavior-neutral for the one existing caller (`PipelineDispatcher#execute`,
which already passes a full `ENV.to_h` copy explicitly) and required for
this section's allowlist to mean what it says. `Pipeline::Subprocess` also
gained `stdin:` support (a writer thread symmetric to the existing
stdout/stderr readers) since this section's design requires the prompt to
travel over stdin. This section is deliberately infra-only — env var
contract, subprocess secrets policy, credential/network reachability —
settled before `Pipeline::Ruby::TranslateBatch` or any other job-type
stub's internals get written; `Pipeline::ClaudeCode` is the backend-seam
primitive (the direct analog of `claude_code_agent.py`'s `call()`), not
prompt/orchestration logic — building that is R4+'s job, still open.

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

**Status: built 2026-07-24 — `Pipeline::Skill` (the shared interface,
`app/services/pipeline/skill.rb`) and `Pipeline::Skills::BibleLookup`
(`app/services/pipeline/skills/bible_lookup.rb`), with unit specs
(`BibleSearchService` stubbed) and integration specs (real DB, real
`BibleSearchService`, only `VoyageClient` stubbed).** Built as designed,
with no deviations from the shape below. The end-to-end layer named in
this section's testing strategy still isn't meaningful — R1 exists now,
but nothing yet builds the "local" tool loop that would call this skill
instance directly, and R3's bridge (below) has no caller wiring it to a
real translation call either.

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

**Status: built 2026-07-24 — `mcp` (0.8.0) moved to the Gemfile's main
group; `Pipeline::Mcp::ServerContext` (`Data.define`), `Pipeline::Mcp::BibleLookupTool`
(the adapter), and `bin/mcp_skill_bridge` (the subprocess entrypoint), all
with passing specs.** One real, deliberate deviation from the design below:
`server_context` carries `novel_directory_name` (a String), not "a novel
id" as this section's illustrative language suggested — because R2's
actually-built `Pipeline::Skills::BibleLookup` takes `novel_directory_name:`
in its constructor (matching Python's exact interface), and there's no
reason to plumb an id through only to look up the same directory-keyed
record a different way. Also new since the design pass: the adapter
redirects `$stdout` to `$stderr` for the duration of each `#execute` call
(restored in an `ensure`), matching this section's own stdin/stdout-
discipline requirement — the design named the requirement but didn't
pick where it lives; it lives in the adapter, since that's the Ruby
equivalent of where `skill_bridge.py` does the same redirect.
`bin/mcp_skill_bridge` was smoke-tested directly over stdin/stdout
(`tools/list` and a real `tools/call` against a real Rails boot) to
confirm the full chain works, not just under mocks — everything else
below was verified against the actual installed `mcp` gem's API, not
guessed. The actual installed `mcp` gem's API doesn't match either this
document's own prior assumptions or the original artifact's, on two
separate points, both corrected below against the gem's real source.

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

## R4 — `translate_batch` orchestration

**Status: designed 2026-07-24, same session as R0–R3's build — no Ruby
code written.** This is the first phase whose design actually exercises
R1's `Pipeline::ClaudeCode`, R2's `Pipeline::Skills::BibleLookup`, and R3's
bridge together, end-to-end — everything before this point was
infra/plumbing with no real caller.

- **Goal:** Port `translate_batch.py`'s orchestration into
  `Pipeline::Ruby::TranslateBatch` — the first Ruby code to build a real
  `--mcp-config` pointing at `bin/mcp_skill_bridge` and drive
  `Pipeline::ClaudeCode` with it, replacing the stub that currently raises
  `NotImplementedError`.
- **Scope reduction, stated up front:** most of `translate_batch.py`'s own
  surface — `_parse_args`, `_prompt_chapters`, `_prompt_confirm`, the
  interactive stdin loop — is CLI-only and needs no port at all.
  `TranslationJob` already carries `chapter_start`/`chapter_end` from the
  web UI's job-creation form, so chapter selection is a solved problem
  before R4 starts. Actual scope: reference-file loading, per-chapter
  prompt assembly, `mcp_config` construction, sequential
  `Pipeline::ClaudeCode` calls, writing outputs to the exact path
  `PipelineJob#attach_translated_outputs` already depends on, progress
  reporting, partial-failure handling, and the `[stdout, stderr, success?]`
  return contract `PipelineDispatcher` already expects from every
  `Pipeline::Ruby::*` stub.
- **Responsibility boundary, stated explicitly so it stays true through
  implementation:** `TranslateBatch` orchestrates. It does not translate,
  search, format bible output, implement MCP, or implement subprocesses —
  R1–R3 already own those. It only coordinates: load references → build
  context → build prompt → invoke `Pipeline::ClaudeCode` → write file →
  report progress. Every design point below composes an existing
  R1/R2/R3 component rather than growing new logic that duplicates one.
  If the eventual implementation starts accumulating formatting logic,
  filesystem helpers, bridge-construction details, or retry logic inline,
  that's the signal a small helper object belongs there instead — named
  here so it's checked at build time, not discovered after the fact.
- **Design:**
  - **Return contract — verified against the real call site, not assumed.**
    `PipelineDispatcher#dispatch_ruby` does
    `when "translate_batch" then Pipeline::Ruby::TranslateBatch.call(@job)`,
    and that return value flows straight through `dispatch_ruby` →
    `PipelineDispatcher#call` → `PipelineJob#perform`'s
    `stdout, stderr, success = PipelineDispatcher.call(translation_job)`.
    R0.4 built this pass-through specifically so "the dispatcher never
    changes again" — R4 is the first stub whose `.call` actually has to
    return a real `[stdout, stderr, success?]` triple instead of raising.
    Easy to miss since nothing in R1–R3 ever exercised it.
  - **Reference-file loading is genuinely new Ruby functionality, not a
    redirect to something that already exists.**
    [[hawk_translations_rails_refactor_r0_design]] already flagged that
    nothing in Ruby reads `novel_info.md`/`translation_guidelines.md`/etc.
    into prompt context today — `BibleMarkdownParser` parses bible markdown
    into DB records (a different job) and `VoiceCalibrationDocWriter` only
    *writes* `voice_calibration.md`. R4 needs a Ruby
    `load_reference_files(novel_dir)` that reads the same 8 files
    (`NOVEL_FILES` in `config.py`) straight off disk as raw strings, exactly
    like Python — never a parsed/DB representation. Missing files return
    `""` (matches `_read_file`'s warn-and-continue, not raise — an
    unpopulated bible shouldn't block translation). Python's
    `ThreadPoolExecutor` parallel read is an optimization, not a
    correctness requirement — 8 small file reads are cheap enough
    sequentially; naming this so it reads as a deliberate simplification,
    not an oversight.
  - **Narrator-note regex checked individually, not assumed safe by
    category.** `_extract_narrator_note`'s pattern
    (`^## Narrator Note\s*\n(.*?)(?=^##|\Z)`, MULTILINE|DOTALL) uses no
    `\w`/`\d`-class escape — the exact Unicode-vs-ASCII gap the original
    artifact's design review flagged (Ruby/Onigmo's `\w` is ASCII-only by
    default; Python's is Unicode-aware) doesn't apply to this particular
    regex. Checked directly rather than assumed safe because "it's usually
    English"; `novel_info.md` can legitimately contain Korean elsewhere in
    the same file. Every regex touched during R4's actual port needs the
    same individual check, not a blanket "we already knew about this class
    of bug."
  - **Prompt assembly — a direct string port, verified by input-diffing, not
    output-diffing.** `TranslationContext` becomes a 9-field Ruby value
    object (`Data.define`, same precedent as `Pipeline::Mcp::ServerContext`);
    `build_translation_prompt` and `prompt_utils.py`'s `section()` helper
    port as the same section-joining logic. Per the original artifact's own
    guidance for R4–R6: diff the constructed **inputs** (the actual
    `system_prompt` string) against Python's output for a representative
    batch of real chapters — across at least one novel with populated bible
    files and one with mostly-empty ones — *before* ever comparing
    translated output. Output-diffing alone is a weak signal since LLM
    output isn't deterministic given an identical prompt; this is
    acceptance-criteria-level, not a nice-to-have.
  - **`mcp_config` is simpler than Python's `_mcp_config_json`, not a
    straight port of its shape.** Python serializes a list of skill specs
    via `bridge_spec()` for `importlib`-based reconstruction inside the
    bridge subprocess. R3's Ruby bridge already hardcodes its one
    registered tool class and only needs
    `HAWK_BRIDGE_NOVEL_DIRECTORY_NAME` — so R4's `mcp_config` only needs a
    `command`/`args`/`env` triple pointing at `bin/mcp_skill_bridge`, no
    spec-serialization step at all.
    - **Command/args must resolve past the shebang, mirroring Python's own
      `sys.executable` + script-path pattern** (`"command": sys.executable,
      "args": [str(_BRIDGE_SCRIPT)]`) — never relying on
      `bin/mcp_skill_bridge`'s own `#!/usr/bin/env ruby` shebang, which
      re-triggers a bare `PATH` search at spawn time, the exact thing R1's
      `CLAUDE_BIN` resolution exists to avoid for the `claude` binary.
    - **Concrete, verified gotcha on this box: `ruby` on `PATH` is an rbenv
      shim, not the real interpreter.** `which ruby` resolves to
      `~/.rbenv/shims/ruby` — a dispatch script that does its own internal
      `PATH`/`.ruby-version` resolution. Treating that shim path as
      "absolute, no further `PATH` search needed" (the way `CLAUDE_BIN`'s
      logic correctly treats the real `claude` binary) would be wrong here,
      since the shim's own internals still depend on environment.
      `rbenv which ruby` resolves the real interpreter
      (`~/.rbenv/versions/3.4.2/bin/ruby` on this box) — *that* path is
      what should be resolved once and cached, mirroring
      `TranslationConfig#resolve_claude_bin`'s discipline but pointed one
      layer deeper than a bare `which ruby` would land. States as a general
      requirement, not a hardcoded path: whatever resolves the bridge's
      interpreter must resolve past version-manager shims (rbenv/rvm/asdf),
      not just past a bare command name.
    - **`BUNDLE_GEMFILE` needs to be set explicitly, not left to
      working-directory discovery.** `bin/mcp_skill_bridge`'s
      `require_relative "../config/environment"` triggers `Bundler.setup`
      via `config/boot.rb`, and Bundler's default Gemfile discovery walks
      upward from `Dir.pwd` — not from the required file's own path. Since
      it's `claude`'s own subprocess-spawning code, not this app's, that
      decides the bridge's working directory, relying on a favorable `cwd`
      is fragile. Set `BUNDLE_GEMFILE` to this app's Gemfile's absolute path
      explicitly in the env this design builds for the bridge.
  - **Bridge subprocess env — a different trust boundary from the `claude`
    CLI's, needs its own allowlist, not R1's reused verbatim.** R1's
    `HOME` + `MCP_CONNECTION_NONBLOCKING`-only allowlist exists to keep a
    third-party, OAuth-authenticated binary away from
    `RAILS_MASTER_KEY`/`DATABASE_URL`. The bridge is the opposite case: it's
    this app's own code, and it must boot enough Rails to reach
    `BibleSearchService`/ActiveRecord — it structurally needs some of
    exactly what R1 deliberately excludes.
    - **Checked against the real config, not assumed:** development's
      `config/database.yml` has no `host`/`username`/`password` — it
      connects via local Postgres peer auth, needing no `DATABASE_URL` or
      `HAWK_DATABASE_PASSWORD` at all. Production's connection is fully
      `DATABASE_URL`/`HAWK_DATABASE_PASSWORD`-driven (Kamal-injected secret
      env, per `config/deploy.yml`'s `env.secret` list). Since
      hawk-translations only runs via local systemd today (see
      [[hawk_translations_shared_oracle_vm]]), the actual current target
      needs none of the production DB secrets forwarded — the same
      "no production instance yet" reasoning R1 already used for the OAuth
      credential question, applied here to a second subprocess.
    - **`config/master.key` already exists on disk** (verified:
      `-rw------- ... config/master.key`) — Rails falls back to reading
      that file directly when `RAILS_MASTER_KEY` isn't set, so the
      dev/local target needs that secret forwarded even less than the DB
      ones above.
    - **Recommended allowlist for the bridge's env, built additively from
      `{}`** (same discipline as `Pipeline::ClaudeCode`'s allowlist):
      `RAILS_ENV`, `HOME`, `BUNDLE_GEMFILE`, and
      `HAWK_BRIDGE_NOVEL_DIRECTORY_NAME` (already named in R3). Explicitly
      **not** included for the current target: `DATABASE_URL`,
      `HAWK_DATABASE_PASSWORD`, `RAILS_MASTER_KEY`, `ANTHROPIC_API_KEY` —
      none are needed to boot Rails and reach Postgres on this box today.
      **The bridge's allowlist is derived independently from the minimum
      environment required to boot Rails — not by starting from R1's
      `claude`-CLI allowlist and modifying it.** The two lists look similar
      only because both happen to be minimal for their own subprocess;
      keeping them derived separately is what keeps the "different trust
      boundary" framing above true if either allowlist grows later for
      unrelated reasons.
      **Flagged as required cleanup to revisit, not solved here,** the
      moment a real `kamal deploy` happens — a deployed bridge would need
      `DATABASE_URL` + `HAWK_DATABASE_PASSWORD` added (and possibly
      `RAILS_MASTER_KEY`, depending on whether `config/master.key` is baked
      into the production image — a build/deploy question out of scope
      here, same as R1's parked OAuth-provisioning question).
    - **Open, unverified question — needs a real smoke test, not a
      guess:** whether the `claude` CLI merges an `--mcp-config` server's
      own `env` object into a copy of `claude`'s *own* (already-stripped)
      environment, or into `claude`'s full inherited environment. This is
      the same shape of gotcha R1's build surfaced for `Process.spawn`
      itself (`env:` merges into a full copy of the parent's environment by
      default, requiring `unsetenv_others: true` to actually replace it) —
      a closed-source CLI's internal subprocess-spawning behavior can't be
      verified by reading this repo. R3's own bridge smoke test only
      exercised `bin/mcp_skill_bridge` directly over stdio, never via a real
      `claude --mcp-config` spawn. R4's build should smoke-test this
      explicitly (a real `claude -p` call with the real `--mcp-config`,
      confirming the bridge process actually reaches Postgres) before
      trusting the allowlist above is sufficient.
    - **Secrets-in-JSON-argv, extending R0.1's existing logging
      constraint:** whatever env values end up in `mcp_config`'s `env`
      object get serialized into the `--mcp-config` JSON string, itself one
      of `Pipeline::ClaudeCode`'s own argv elements. R0.1 already forbids
      logging full `cmd`/`env` for exactly this reason; that prohibition
      now explicitly covers this argument's *value* too, not just the
      general rule — `mcp_config.to_json` must never appear in logs, since
      it may carry `BUNDLE_GEMFILE`/`RAILS_ENV` today and DB secrets once a
      deployed target needs them.
  - **`web_search` prompt/toolset mismatch — a real gap, not cosmetic.**
    `build_translation_prompt`'s literal instruction text tells the model:
    *"If you encounter a term... use the web_search tool to look it up...
    Flag only terms that remain unresolvable after searching."* R3
    explicitly scoped `web_search` out — only `bible_lookup` is wired in the
    Ruby bridge. Porting the prompt text verbatim would ship a system
    prompt that references a tool absent from its own `--mcp-config`. Two
    honest options, not resolved here:
    - **(a)** Strip/reword the `web_search` sentence for the Ruby path,
      accepting a small prompt-text difference from Python's (the
      translator loses the "search before flagging" instruction until
      `web_search` is ported).
    - **(b)** Leave the prompt text unchanged and rely on the MCP dispatch
      layer's own behavior for an unregistered tool name (verified in R3: a
      JSON-RPC `INVALID_PARAMS` error at the SDK's dispatch layer, before
      any adapter runs) being something Claude Code's agentic loop recovers
      from gracefully — plausible but **untested**, so this option's
      fallback behavior is assumed, not confirmed.
    - **Recommendation: (a).** A small, deliberate prompt-text difference is
      more predictable than depending on unverified LLM-side error recovery
      on every chapter that hits an unresolvable term.
  - **Sequential-only, per-chapter — ported faithfully, not
    parallelized.** Matches Python exactly: neither backend has a real
    batch API, so `run_translation_batch`'s per-request loop maps onto a
    plain Ruby `each`. Nothing about the Ruby port changes this.
  - **Partial-chapter failure needs an explicit policy — Python's script
    and Rails' single-job model don't compose for free.** Python's
    `run_translation_batch` catches per-request exceptions, logs them, and
    *continues* — a 10-chapter batch where chapter 4 fails still writes 9
    files and reports "9 done, 1 failed" to whoever's watching stdout.
    `TranslationJob` has exactly one `status` for the whole job; there's no
    per-chapter status column for `translate_batch` the way `preread`'s
    chapters get individual transitions.
    - **Recommended policy:** continue translating remaining chapters after
      one fails (matches Python's actual behavior — don't silently regress
      to "abort on first error"), write every chapter that *does* succeed
      to disk immediately (so `attach_translated_outputs` can pick up
      partial progress even if the job ultimately reports `failed`), and
      mark the overall `TranslationJob` `failed` if **any** chapter failed —
      with the failed chapter numbers and their `error_category` (from
      `Pipeline::ClaudeCode::Result`) in `result_payload`, not a generic
      message. This differs from Python's CLI behavior (which always exits
      "successfully" and just prints a skip list) because a Rails job needs
      one success/failure signal for the UI, and "green while some chapters
      silently failed" is the wrong default for a status a translator
      relies on.
    - **`update_chapters`'s existing `translate_batch`/`success` case is
      all-or-nothing today** (`chapters.update_all(status: "translated")`
      runs only in the `success` branch) — under the policy above, a
      partial failure means `update_chapters` never marks *any* chapter
      `"translated"`, even ones that got a file written and attached. This
      is a real, pre-existing gap the policy surfaces rather than creates —
      flagged for whoever builds R4 to resolve (e.g. a distinct
      partial-success path), not solved in this document.
    - **The policy's implications reach beyond job status, into
      application-level UX questions — named here so they aren't
      discovered later as surprises, not answered here since they're not
      orchestration decisions.** Once a job can be `failed` with some
      chapters already written and attached: should a retry of that job
      re-translate every chapter, or skip the ones that already succeeded?
      Should `attach_translated_outputs` attach the partial set even when
      `status` is `failed`, or only on `success` as it does today? Should a
      translator be able to download a partial batch's output before
      retrying? Each answer constrains the others (e.g. skip-on-retry only
      makes sense if partial attachment already happened) — worth deciding
      together, deliberately, when R4's build reaches the UI/controller
      layer, rather than defaulting silently one at a time.
  - **Error taxonomy reuse — `Pipeline::ClaudeCode::Result#error_category`
    becomes the per-chapter failure signal, not a fresh one.** R1 already
    built a 6-category taxonomy sitting unused until now — R4 is the first
    real caller. A batch that failed on `:timeout` (plausibly worth
    retrying) reads very differently from one that failed on
    `:binary_not_found` (every remaining chapter is certain to fail
    identically) or `:killed` (possible OOM, ties back to R0.3's still-
    unmeasured baseline).
    - **Elevated beyond a single fail-fast-or-not question: the 6 error
      categories split into two structurally different classes, and the
      policy above should not apply uniformly across both.**
      - **Recoverable** — `:timeout`, `:cli_failure`, `:cancelled`: caused
        by this specific chapter's request (a slow response, a transient
        CLI hiccup, a killed job). Chapter 5 failing this way says nothing
        about whether chapter 6 will succeed. "Continue to the next
        chapter" is the right default here — this is the case the
        recommended policy above was written for.
      - **Fatal** — `:binary_not_found`, `:killed` (when traceable to OOM
        rather than a one-off), and any future "bridge failed to boot" /
        "config invalid" category: caused by something true for the whole
        job, not the one chapter. If chapter 1 fails because the `claude`
        binary doesn't exist, chapters 2 through 10 are guaranteed to fail
        identically — "continue anyway" only burns the remaining budget of
        the 4-hour job timeout on outcomes already known.
      - **Not resolved here, deliberately:** which specific categories
        route to which branch, and where that branching logic lives (a
        per-chapter check inside the `each` loop, most likely). Naming the
        two classes explicitly — rather than leaving "should we fail-fast"
        as a single open question — is the point of this bullet; the branch
        itself is still real, undecided work for R4's build, not something
        this document quietly settles by only describing examples.
  - **Progress reporting — the same file-based protocol, not a new
    mechanism.** `PipelineJob#perform`'s polling thread is untouched by this
    design (out of scope for R4, same carve-out R0.1 already took) — it
    reads `/tmp/hawk_job_#{id}.progress` regardless of which implementation
    is dispatched. Since `Pipeline::Ruby::TranslateBatch` runs in-process on
    the same thread as `PipelineJob#perform` (no subprocess wrapping the
    whole job the way Python's script is wrapped today), it still needs to
    *write* to that same path after each chapter completes — mirroring
    `src/progress.py`'s `report_progress` (percent = chapters written so
    far / total, clamped 0–100) — not call
    `translation_job.update!(progress_pct:)` directly, which would race the
    polling thread's own `update_all` reading a file nothing writes to
    anymore. The job ID for the file path comes from `@job.id`, replacing
    Python's `HAWK_JOB_ID` env var read — there's no subprocess boundary
    left to cross that env var over.
  - **Output file writing must match the exact contract
    `attach_translated_outputs` already depends on.** `derive_output_path`'s
    format (`chapters/Chapter {N}.txt`, one file per chapter, written as
    each chapter completes rather than batched at the end) isn't a
    stylistic choice R4 can revisit — `PipelineJob#attach_translated_outputs`
    (untouched, unrelated to this design) already expects exactly this path
    and reads it after the job reports success. Same "output is part of the
    model-facing interface" discipline R2 stated for `bible_lookup`'s
    formatters, applied here to file-naming instead of text formatting.
  - **Output directory integrity — the invariant underlying the next two
    findings.** `TranslateBatch` implicitly assumes exclusive ownership of
    its output directory for the duration of a translation job: that a
    chapter file, once it exists, is either absent or complete, and that
    nothing else is writing into `chapters/` at the same time. Neither half
    of that assumption currently holds. Writing it down as a named
    invariant here, rather than leaving it implicit, is what makes the two
    findings below legible as violations of the *same* assumption instead
    of two unrelated edge cases.
  - **Finding 1 — chapter writes aren't atomic, and R4's own fatal category
    makes the failure mode concrete. Recommended design change, not just a
    flagged gap.** `translate_batch.py:210` does a plain
    `output_path.write_text(...)` — no temp-file-then-rename. If the
    process is OOM-killed mid-write (this design's own **fatal**
    `:killed` category, above), `chapters/Chapter {N}.txt` exists on disk
    truncated, and `attach_translated_outputs` has no way to distinguish
    that from a genuinely complete chapter — it attaches the corrupt file
    as if translation succeeded. This is a pre-existing gap in Python, but
    naming `:killed` as fatal in this same document raises the cost of
    porting the gap forward unexamined.
    - **Recommended:** write each chapter's translated text to
      `chapters/Chapter {N}.txt.tmp` first, then `File.rename` it into
      `chapters/Chapter {N}.txt` once the write is flushed. `rename` is
      atomic on the same filesystem, so after any crash — `:killed` or
      otherwise — exactly one of two states is observable: the old file
      (if this is a retry) still present and complete, or the new file
      present and complete. Never a truncated file in the completed path.
      This is a small, low-risk implementation change with no observable
      behavior difference other than removing the corruption window —
      exactly the kind of infrastructure improvement a rewrite should make
      rather than carry forward unchanged, unlike the genuinely undecided
      policy questions elsewhere in this section.
  - **Finding 2 — concurrent `translate_batch` jobs aren't prevented, and
    this is deliberately left unsolved here, not overlooked.** Checked
    against `PipelineJob`: `limits_concurrency to: 1` is gated
    `if local_llm_endpoint?` — it doesn't apply to the `claude_code`
    backend R4 targets. Nothing stops two `TranslateBatch` jobs for the
    same novel (or overlapping chapter ranges) from running at once via
    Solid Queue, both writing the same `chapters/Chapter {N}.txt` paths —
    a second violation of the output-directory-integrity invariant above,
    independent of Finding 1's atomicity fix (atomic writes make each
    individual write safe; they don't make two competing writers to the
    same final path coherent — last rename wins).
    - **Deliberately not solved in this document:** preventing overlapping
      jobs is an application-scheduling policy question (reject the second
      job? queue it? cancel the first? allow both and accept last-write-
      wins?), not an orchestration concern — `TranslateBatch` becoming
      responsible for distributed locking would be scope creep past the
      "orchestrates, doesn't own policy" boundary stated earlier in this
      section. Named here as a real, verified architectural finding
      the same way `update_chapters`'s all-or-nothing gap and the
      `web_search` mismatch are — not left to be rediscovered only once
      it surfaces as a corrupted-output bug report.
- **Acceptance criteria:**
  - `Pipeline::Ruby::TranslateBatch.call(job)` returns
    `[stdout, stderr, success?]`, matching `PipelineDispatcher#dispatch_ruby`'s
    existing pass-through contract — verified against the real call site,
    not assumed.
  - The implementation reads as an orchestrator (load references → build
    context → build prompt → invoke `Pipeline::ClaudeCode` → write file →
    report progress), not as a place where translation, search, bible
    formatting, MCP, or subprocess logic gets reimplemented — if formatting,
    filesystem, bridge-construction, or retry logic starts accumulating
    inline, that's a signal to extract a helper object, checked against this
    criterion rather than discovered later.
  - Chapter selection is read from `job.chapter_start`/`job.chapter_end` —
    no CLI-style argument parsing, interactive prompting, or novel-name
    disambiguation is ported; those exist only because `translate_batch.py`
    is also a standalone CLI tool, a role the Rails job doesn't need.
  - All 8 `NOVEL_FILES` reference files are read directly from disk per
    novel, exactly as Python does — not derived from `BibleMarkdownParser`'s
    DB records or any other structured source. Missing files produce empty
    strings, not errors.
  - The narrator-note regex, and any other regex touching novel content, is
    checked individually for ASCII-only-`\w`-vs-Unicode gaps before
    porting — not assumed safe by category.
  - The assembled `system_prompt` byte-matches Python's
    `build_translation_prompt` output for a representative sample of real
    chapters (at least one novel with populated bible files, one with
    mostly-empty ones), checked before ever comparing translated output.
  - The bridge's interpreter and script path are resolved past any version-
    manager shim (verified on this box: `which ruby` is an rbenv shim, not
    the real interpreter) and invoked as `command` + `args` rather than via
    the script's own shebang.
  - `BUNDLE_GEMFILE` is set explicitly (absolute path) in the bridge's env,
    not left to working-directory-based Gemfile discovery.
  - The bridge's env is an explicit allowlist built additively from `{}`
    (not R1's `claude`-CLI allowlist reused verbatim) — for the current
    local/dev target: `RAILS_ENV`, `HOME`, `BUNDLE_GEMFILE`,
    `HAWK_BRIDGE_NOVEL_DIRECTORY_NAME`. `DATABASE_URL`,
    `HAWK_DATABASE_PASSWORD`, `RAILS_MASTER_KEY`, and `ANTHROPIC_API_KEY`
    are named explicitly as not required for this target today, and as
    required cleanup to revisit (not guess at) the moment a real
    `kamal deploy` happens. This allowlist is derived independently from
    Rails' own minimum boot requirements — not by copying and trimming R1's
    `claude`-CLI allowlist — so the two stay free to diverge if either
    changes later for unrelated reasons.
  - Whether `claude`'s own MCP-server spawn merges a server's `env` into a
    copy of its stripped env or its full inherited one is named as an open
    question requiring a real smoke test (an actual `claude -p` call with a
    real `--mcp-config`, confirming the bridge reaches Postgres) before
    R4's build trusts the allowlist above — not assumed either way.
  - `mcp_config.to_json`'s value is added to R0.1's existing "never log full
    cmd/env" prohibition, since it may carry sensitive values once a
    deployed target needs them in its env.
  - The `web_search`-instructing sentence in the ported system prompt is a
    deliberate decision (strip it, matching R3's `bible_lookup`-only
    bridge) — not a silent carry-over of prompt text referencing a tool
    absent from the Ruby toolset.
  - Chapters are translated strictly sequentially, one `Pipeline::ClaudeCode`
    call per chapter — no concurrency introduced that neither backend
    actually supports.
  - A chapter's failure does not abort the batch by default (matching
    Python's per-chapter try/except) — but the 6 error categories are named
    as splitting into **recoverable** (`:timeout`, `:cli_failure`,
    `:cancelled` — specific to the one chapter) versus **fatal**
    (`:binary_not_found`, OOM-traceable `:killed` — true for the whole job,
    guaranteed to recur on every remaining chapter). Which categories route
    to which branch, and where that check lives, is named as a real,
    undecided branch point for R4's build — not silently resolved by
    "continue" applying uniformly to every category, and not left as a
    single undifferentiated "should we fail-fast" question either.
  - The partial-failure policy's downstream UX questions — whether a retry
    skips chapters that already succeeded, whether a `failed` job's partial
    output is attached or downloadable before retrying — are named as
    real, connected, application-level questions to decide together at the
    controller/UI layer, not answered by this orchestration-level document
    and not left undiscovered until they surface as bugs.
  - Every successfully translated chapter is written to
    `chapters/Chapter {N}.txt` immediately, in the same location/format
    `PipelineJob#attach_translated_outputs` already depends on — not
    batched until the end, and not a new path or format.
  - The overall `TranslationJob` is marked `failed` if any chapter failed,
    with `result_payload` naming which chapters failed and their
    `error_category` — not a single generic failure string.
  - `update_chapters`'s existing all-or-nothing `translate_batch`/`success`
    branch is named as a gap this policy surfaces (no partial-success
    chapter-status path exists today) — flagged for R4's build to resolve,
    not solved in this document.
  - Progress is reported by writing to `/tmp/hawk_job_#{job.id}.progress`
    after each chapter, matching `PipelineJob`'s existing polling-thread
    contract — not a new progress-reporting mechanism, and not a direct
    `translation_job.update!(progress_pct:)` call that would race the
    polling thread.
  - Each chapter's translated text is written to a `.tmp` path first, then
    moved into `chapters/Chapter {N}.txt` via `File.rename` (atomic on the
    same filesystem) — never written directly to the final path. This is a
    recommended implementation change for R4's build, not merely a flagged
    gap: after any crash, including the fatal `:killed`/OOM case, exactly
    one of "old file complete" or "new file complete" is observable,
    never a truncated final file.
  - The absence of a concurrency guard for overlapping `translate_batch`
    jobs targeting the same novel is named as a real, verified
    architectural finding (`PipelineJob`'s `limits_concurrency` only
    applies `if local_llm_endpoint?`, not to the `claude_code` backend) —
    and is explicitly *not* resolved here, since preventing overlapping
    jobs is an application-scheduling policy decision, not something
    `TranslateBatch` should own. Named as an open question for a later
    layer to decide, the same way `update_chapters`'s gap and the
    `web_search` mismatch are named rather than silently carried forward.
  - No Ruby implementation code is written as part of this section — a
    separate, later pass, same discipline as R0–R3.

---

## R5 — `post_translation_review` and `voice_calibration` orchestration

**Status: designed 2026-07-25, no Ruby code written.** Scoped and designed
together (confirmed via clarifying question before starting) rather than
one job type at a time the way R4 was scoped alone — both are single-call
prompt-build/parse flows, much smaller than R4's per-chapter loop, and
share real pieces (a prompt-section helper, `Pipeline::ClaudeCode`'s call
shape, and — after a revision pass, below — the entire proposal/review/
commit lifecycle), so designing them apart would mean re-deriving the same
shared decisions twice.

**Revised same session, after user review, before any Ruby code was
written — two rounds of feedback, both substantive enough to change the
design's shape, not just its details:**

**Round 1 (robustness/security pass):** the original design had
`post_translation_review` auto-apply proposed edits and story updates
directly to bible files, hardened with a uniqueness check and atomic
writes. User feedback identified real gaps atomic rename doesn't close
(lost updates from concurrent writers, TOCTOU staleness between the LLM
call and the write, unbounded LLM-output size, permissive parsing) and
asked whether auto-apply was even the right call given a proven
human-review pattern already exists (`voice_calibration`'s cards flow).
Agreed and adopted below, with some refinement rather than verbatim
adoption (see each item's reasoning inline): locking, live re-validation
at write time (a refinement of a proposed whole-file-hash staleness check
— reasoning below), size/count caps, stricter parsing, `Data.define` value
objects instead of hashes, story-update deduplication.

**Round 2 (the auto-apply question, escalated):** user's answer went
further than "add a review gate to edits" — **all three bible-review
mutation types (new entries included, not just edits and story updates)
now require human review**, on the reasoning that bible entries feed
forward as reference context into every future translation/review call,
so an unvetted new entry compounds silently and is not actually lower-risk
than an edit just because it's additive. This is also what the original
design should have done for consistency with `voice_calibration`, which
already gates its `new_pattern` cards, not just `retirement` cards — an
inconsistency in the original design, not a deliberate asymmetry.

**Consequence, identified by the user, not incidental:** this makes
`post_translation_review` and `voice_calibration` structurally identical
orchestrators for the first time — both become *read → prompt → call →
parse → emit review cards*, and **neither owns persistence**. The
remainder of this section is restructured around that convergence: a
target shared abstraction (named, not built), concrete per-domain writer
objects that own every hardening measure named above, and a staleness
mechanism formalized for the now-asynchronous (human-latency-bound, not
just LLM-latency-bound) gap between proposal and commit.

- **Goal:** Port `run_review.py` (post-translation bible review) into
  `Pipeline::Ruby::PostTranslationReview`, and `calibrate-voice.py` (voice
  calibration) into `Pipeline::Ruby::VoiceCalibration`, replacing both
  stubs' `NotImplementedError`. **Post-revision, this is narrower than a
  literal port of either script's end-to-end behavior:** both classes now
  produce review proposals only; `run_review.py`'s auto-apply behavior is
  deliberately *not* ported (see the auto-apply decision below) in favor
  of a review-then-commit flow matching `voice_calibration`'s existing
  pattern.
- **Scope reduction, stated up front, same pattern as R4:** neither
  Python script's full surface needs a port. `src/bible_review/runner.py`
  and `src/voice_calibration/discussion.py` are CLI-only — an interactive
  `input()`-driven confirmation loop and a multi-turn "discuss with Opus"
  chat, both explicitly for terminal use only (`run_review.py`'s own
  docstring: *"For interactive terminal use, continue using review.py — it
  is untouched"*). Neither is reachable from Rails today and neither needs
  a Ruby port — not even as a reference for the new human-review step
  below, which follows `voice_calibration`'s existing web-based
  accept/skip pattern instead, not `runner.py`'s terminal-`input()` one.
  Chapter selection is also out of scope for both, same reasoning as R4:
  `TranslationJob#chapter_start` (already supplied by the web
  job-creation form; `voice_calibration` jobs are additionally validated
  to target an already-`reviewed` chapter — see
  `TranslationJob#voice_calibration_chapter_reviewed`) replaces Python's
  CLI argument parsing and "latest translated chapter" resolution
  entirely.
- **Auto-apply decision — reconsidered and reversed during review, not a
  parity port.** The original design matched `run_review.py`'s current
  production behavior exactly: new entries written immediately, proposed
  edits and story updates auto-applied, no human confirmation step for
  any of it. Technical hardening (uniqueness checks, atomic writes) closes
  the corruption/crash failure modes but not the editorial one — a
  well-formed, uniquely-matched, correctly-applied edit can still just be
  *wrong*, and only a human gate closes that. Given `voice_calibration`
  already has a proven, shipped pattern for exactly this
  (`VoiceCalibrationReviewController`'s accept/revise/skip flow), and
  given bible entries feed forward as reference context into every
  future translation and review call — so an unvetted new entry compounds
  silently, and is not actually lower-risk than an edit just because it's
  additive — **all three `post_translation_review` mutation types (new
  entries, proposed edits, story updates) now require human review before
  anything is written to disk**, matching `voice_calibration`'s existing
  new-pattern-and-retirement symmetry rather than carving out an
  inconsistent "additive stuff skips review" exception. This is real new
  scope beyond the original goal — a second review UI, not just an
  orchestration class — accepted deliberately in exchange for closing the
  one risk category technical hardening alone cannot.
- **Backend decision — a real, deliberate production behavior change for
  `post_translation_review`, confirmed with the user rather than assumed.**
  Checked against `docs/DECISIONS.md`'s 2026-07-21 entries: `calibrate-voice.py`
  already moved to the `claude_code` backend that day (quality-ceiling
  reasoning: local-model review output trended generic/templated), but
  `run_review.py` was explicitly named as one of "the remaining 7 pipeline
  scripts" that **stayed on the local Ollama backend** (`src/agent.py`,
  unconditionally — it doesn't even read `TRANSLATION_BACKEND`/
  `CALIBRATION_BACKEND`, unlike `calibrate-voice.py`, which does select via
  `get_backend(CALIBRATION_BACKEND)`). Porting `post_translation_review`
  faithfully would mean building a Ruby "local"/Ollama call path — the
  exact piece [[hawk_translations_rails_refactor_r0_design]] already
  flagged as deferred indefinitely, out of scope for R4+. **Decision
  (user-confirmed): both job types move onto `Pipeline::ClaudeCode`.** This
  extends the same quality-ceiling reasoning that already moved
  `calibrate-voice.py` off local, rather than reversing the earlier
  local-port deferral or leaving `post_translation_review` on Python
  indefinitely. Concretely: `Pipeline::Ruby::PostTranslationReview`'s
  design below is **not** a line-for-line port of `run_review.py`'s
  backend call — it replaces `src/agent.py`'s OpenAI-compatible call with
  `Pipeline::ClaudeCode`, same as `Pipeline::Ruby::VoiceCalibration` does
  for `calibrate-voice.py`. Every other part of `run_review.py` (reading,
  prompting, parsing, writing) is still a faithful port.
- **No `--mcp-config`/bridge subprocess for either job type — verified by
  reading both prompts, not assumed by category.** Neither
  `bible_review/prompt_builder.py`'s system prompt nor
  `voice_calibration/prompt_builder.py`'s mentions `bible_lookup`,
  `web_search`, or any tool-use instruction — both are plain text-in/
  text-out review calls. So R5 needs none of R3's bridge machinery: no
  `mcp_config` construction, no `bin/mcp_skill_bridge` spawn, no bridge env
  allowlist, no `ruby`-shim resolution, none of R4's `--mcp-config`-shaped
  open questions. `Pipeline::ClaudeCode.call(system_prompt:, user_message:)`
  is invoked with `mcp_config: nil` for both — this is genuinely simpler
  than R4, not merely smaller in code volume. One consequence: unlike R4,
  R5's build has no equivalent of R4's "smoke-test the bridge before
  trusting the allowlist" blocker, so it can be built independently of R4,
  in either order.
- **Responsibility boundary — narrower than R4's, and identical between
  the two classes post-revision.** Both `Pipeline::Ruby::*` classes
  orchestrate only: read files → build prompt → call `Pipeline::ClaudeCode`
  → parse response → emit typed review cards. **Neither writes to disk.**
  Persistence is a separate, later concern owned by a human-reviewed
  commit step (below) — a stricter boundary than R4's "orchestrates,
  doesn't own policy" framing, since these two classes don't even reach
  the write path, not just don't reimplement it. Neither implements bible
  parsing (`BibleMarkdownParser`'s job, unrelated), MCP, or subprocess
  handling (R1/R3 own those already). If either build starts accumulating
  inline formatting, validation, or filesystem logic, that's the signal
  it belongs in the writer (below) instead, not the orchestrator.
- **Target shared abstraction — named as the direction to design toward,
  explicitly not built in this pass.** Now that both orchestrators share
  one lifecycle (*generate proposals → human review → commit through a
  hardened writer*), the natural end state is a generic reviewable-job
  layer with per-domain specifics isolated to one place:
  - **`ReviewCard`** — the typed payload contract every card conforms to
    (an `id`, a `card_type` discriminator, a `decision`, and
    type-specific fields), already the de facto shape
    `voice_calibration`'s cards use today; `post_translation_review`'s new
    cards (below) are designed to fit the same contract from day one.
  - **A generic review-workflow layer** (job/card lookup by id, decision
    validation and persistence back to `result_payload`) — today
    duplicated wholesale if a new controller just copies
    `VoiceCalibrationReviewController`. **Not extracted now** — the two
    controllers below are still separate classes — but the new one is
    named `PostTranslationReviewController` (mirroring the existing
    `voice_calibration_review_controller.rb`'s job-type-based naming) and
    not `BibleReviewController`, deliberately: a job-type name doesn't
    presuppose a domain-flavored identity the way "Bible" does, so lifting
    its generic show/update mechanics into a shared concern later doesn't
    require a rename first. Its `show`/`update` actions should be written
    against `job.cards`/`job.result_payload` in a way that doesn't
    hard-code voice-calibration-specific assumptions, so the lift is
    mechanical when it happens — not attempted as part of R5.
  - **Per-domain `Writer` objects** — the only place domain-specific
    persistence logic lives. `voice_calibration`'s already exists in
    substance (`VoiceCalibrationDocWriter` plus
    `VoiceCalibrationReviewController#apply_card!`'s dispatch, both
    shipped, both untouched by this design). `post_translation_review`
    gets a new one, `BibleReviewWriter` (below) — a domain-flavored name
    is right here, unlike the controller, since the user's own framing for
    this abstraction names the writers by domain
    (`VoiceCalibrationReviewWriter`/`BibleReviewWriter`) while keeping the
    controller and card layers generic. **Consequence worth stating
    explicitly:** every hardening measure below (locking, live
    re-validation, atomic rename, size limits, deduplication) lives in
    `BibleReviewWriter`, not in `Pipeline::Ruby::PostTranslationReview`.
    This creates a single trusted boundary for bible-file mutations — if
    another workflow ever needs to modify these files, it inherits these
    protections by going through the writer, instead of a third
    implementation reinventing (or forgetting) them.
- **Design:**
  - **Shared prerequisite 1 — `PromptUtils.section`/`is_empty`, a joint
    dependency with R4, not R5-only.** `src/prompt_utils.py`'s `section()`
    (used by both Python prompt builders here, and referenced in R4's own
    design above for `translate.py`'s prompt builder) has no Ruby port yet
    — R4 and R5 are the first two designs to need it. Whichever build
    lands first should build it as a small shared module (e.g.
    `Pipeline::PromptUtils`), not duplicate the empty-bible-template
    detection logic (`_EMPTY_MARKERS`) independently in each. Named here so
    neither build "discovers" this dependency mid-implementation and
    invents its own copy.
  - **Shared prerequisite 2 — bible-heading deduplication key, genuinely
    new Ruby functionality, not a redirect to `BibleMarkdownParser`.**
    `src/bible_utils.py`'s `heading_key`/`extract_heading_keys` (Korean-
    parenthetical-aware canonicalization, e.g. `"Ro-an (로안) — English"` and
    `"LOAN (로안) — English"` both key to `"로안"`) has no Ruby equivalent —
    checked directly: `BibleMarkdownParser#parse_heading` extracts
    `(name, korean)` for a *different* purpose (building structured DB
    records) and doesn't derive or expose a canonical dedup key the way
    `bible_utils.py` does. Only `post_translation_review`'s new-entry
    writer needs this (below); `voice_calibration` never writes bible files
    at all (see below), so this is not a joint dependency the way
    `PromptUtils` is.
  - **`post_translation_review`:**
    - **Reader:** `read_translated_chapter` (scans `chapters/`, skips
      filenames containing "korean" or "another translation", matches by
      extracted chapter number — identical file-selection rule to R4's
      chapter-writing side and to `voice_calibration`'s reader below,
      ported once, not three times if a shared helper is worth extracting
      here), `read_bible_files` (the 5 review-relevant files: characters,
      cultural_phrases, locations, story, terminology — Python's
      `ThreadPoolExecutor` parallel read is, same as R4's finding for its
      own 8-file read, an optimization, not a correctness requirement, and
      not worth porting for 5 small sequential reads), `read_novel_info`.
      Missing files return `""`, matching Python's warn-and-continue.
    - **Prompt builder:** `ReviewContext` becomes a 9-field Ruby value
      object (`Data.define`, same precedent as R3's `ServerContext`/R4's
      `TranslationContext`). The system prompt is a static template (four
      bible-entry sub-templates interpolated once, `today`/`chapter_num`
      filled per call) — a direct string port, verified by input-diffing
      the assembled `system_prompt`/`user_message` against Python's output
      for real chapters before ever comparing model output, same discipline
      R4's design already applies to `build_translation_prompt`.
    - **API call:** `Pipeline::ClaudeCode.call(system_prompt:, user_message:,
      mcp_config: nil)` — see the backend decision above for why this is
      `Pipeline::ClaudeCode` rather than a ported `src/agent.py`.
    - **Response parser:** three top-level sections
      (`=== NEW ENTRIES ===` / `=== PROPOSED EDITS ===` /
      `=== STORY UPDATES ===`, "NOTHING TO ADD" → empty), then per-section
      parsing: new entries split on `### file-label` headers into a
      section-key → markdown dict; proposed edits and story updates each
      split on blank-line-separated blocks with `KEY: value` fields
      (`ENTRY`/`FILE`/`CURRENT`/`PROPOSED`/`REASON` and `TYPE`/`UPDATE`
      respectively) via the same field-continuation-line logic Python uses
      (a matched `KEY:` line starts a new field; unmatched lines extend the
      current field's value, supporting multi-line field content).
    - **Card assembly — replaces the old "Writer" step; nothing is written
      to disk from this class.** New entries, proposed edits, and story
      updates each become a typed `Data.define` value object at parse time
      — `NewBibleEntry`, `ProposedBibleEdit`, `StoryUpdate` — rather than
      the raw hashes the original design carried through. Benefits named
      by the user, adopted directly: impossible-invalid-state by
      construction, easier unit testing per card type, and a stable shape
      for the review UI to render against. Each serializes to the same
      card-hash wire format `voice_calibration`'s cards already use
      (`id`, `card_type`, `decision: "pending"` initially, plus
      type-specific fields) — `card_type` values `"new_entry"`,
      `"proposed_edit"`, `"story_update"` (new strings; unlike
      `voice_calibration`'s `"new_pattern"`/`"retirement"`, nothing
      existing consumes these yet, so there's no legacy shape to match).
    - **Staleness fingerprint, captured here at generation time, not at
      commit time.** Immediately after `read_bible_files` (same read
      already needed for the prompt), compute a SHA-256 of each of the 5
      bible files and store them as a `bible_revision` map alongside the
      cards in the emitted payload (`{"cards": [...], "bible_revision":
      {"characters" => "...", ...}}`). This is deliberately *advisory*,
      not enforcing — see "Staleness handling" under the writer below for
      why the actual correctness guarantee lives there instead, and what
      this fingerprint is for.
    - **Response-level size and count limits, checked here, right after
      the API call returns — before any card is constructed or persisted
      to `result_payload`.** A different validation layer than the
      writer's, deliberately: this one is about whether the *response as a
      whole* is sane, not whether a specific mutation is still valid
      against current bible state (that's the writer's job, and depends on
      state that can change between generation and commit — conflating the
      two would mean either re-checking size limits pointlessly at commit
      time or deferring a "the API returned 25 MB of garbage" failure until
      a human opens the review UI, which is worse for both storage and UX).
      Suggested starting bounds (tunable, not load-bearing precision):
      total response ≤ 200 KB, ≤ 50 cards, ≤ 5,000 characters per field.
      Exceeding any bound fails the whole call (`success?: false`, nothing
      persisted) rather than truncating or partially proceeding — a
      malformed-response-shaped failure, not a partial-success one.
    - **Parser strictness — fail-closed at the level that actually
      matters.** If the top-level section markers
      (`=== NEW ENTRIES ===`/etc.) are entirely absent — a likely sign of
      truncated or garbled output — the whole call fails, same "nothing
      written, nothing to review" treatment as exceeding a size limit, not
      three silently-empty sections that look indistinguishable from "the
      model genuinely found nothing to report." Within a present section,
      an individual malformed block (missing a required field, not
      starting with `## `/`ENTRY:` where expected) is rejected and does
      not become a card — logged as a parse failure for that block, not
      silently absorbed into an adjacent entry the way Python's permissive
      splitting would.
    - **Return contract:** `[JSON.generate({cards: cards, bible_revision:
      revision}), stderr, success?]` — the same shape
      `Pipeline::Ruby::VoiceCalibration` returns (below), now that both
      classes emit cards rather than one emitting cards and the other
      mutating files. **Verified this needs no change to
      `PipelineJob#build_result_payload`:** its existing
      `unless job.voice_calibration?` branch already falls through to
      `stdout.presence || "(no output)"` for every other job type,
      including `post_translation_review` — and since these cards need no
      server-side enrichment analogous to `voice_calibration`'s
      retirement→`passage_id` lookup (nothing about a bible card depends on
      a DB id the LLM couldn't have produced itself), the raw JSON stdout
      is exactly what should end up in `result_payload` unchanged. No
      `PipelineJob` changes are in scope for this design.
    - **Progress reporting:** same file-based protocol as R4
      (`/tmp/hawk_job_#{job.id}.progress`, written in-process rather than
      via `HAWK_JOB_ID`-env-var-to-subprocess the way Python's
      `report_progress` works, same reasoning R4's design already states
      for why the env-var handoff doesn't apply to in-process Ruby code).
      Simpler than R4's per-chapter percentage since there's exactly one
      API call: write 50 before the `Pipeline::ClaudeCode` call, 100 after
      — matching `run_review.py`'s own two checkpoints exactly.
  - **`voice_calibration`:**
    - **Reader:** `read_translated_chapter` (same file-selection rule as
      above), `read_voice_calibration` (`bible/voice_calibration.md`,
      empty string if missing — matches `VoiceCalibrationDocWriter`'s own
      tolerance for a not-yet-existing file).
    - **Prompt builder:** `ReviewContext` as a 3-field value object
      (`voice_calibration`, `translated_chapter`, `chapter_num`); static
      system prompt, same input-diffing verification discipline as above.
    - **API call:** `Pipeline::ClaudeCode.call(..., mcp_config: nil)`, same
      as `post_translation_review`.
    - **Response parser:** two top-level sections (`=== NEW PATTERNS ===` /
      `=== RETIREMENTS ===`, "NOTHING TO REPORT" → empty).
    - **No bible-file writes at all — verified directly, a genuine
      simplification, not an oversight to flag.** `calibrate-voice.py`
      never opens `voice_calibration.md` for writing; it only assembles and
      prints a `cards` JSON array. All actual writes (`VoiceCalibrationPassage`
      creation, `VoiceCalibrationDocWriter#upsert`/`#remove`) already exist,
      unchanged, in `VoiceCalibrationReviewController#apply_card!`, gated
      behind the human accept/revise/skip review step the web UI already
      provides. `Pipeline::Ruby::VoiceCalibration`'s job ends at emitting
      the same `cards` JSON `calibrate-voice.py` emits today — nothing in
      this design touches the review/commit flow, and the hardening
      decision above does not apply here since there's no file write to
      harden.
    - **Card assembly — the acceptance-critical contract, verified against
      the real, already-shipped consumers, not guessed at.** New-pattern
      cards: split `new_patterns` on `^## ` headings
      (`_split_patterns`-equivalent), then per-entry regex extraction into
      `{heading, chapter_ref, quote, what_it_demonstrates, wrong_version,
      rule}`, plus `id: "new_pattern_#{i}"` and `card_type: "new_pattern"`.
      Retirement cards: split on `**Retirement candidate` blocks, extract
      `(heading, reason)`, plus `id: "retirement_#{i}"` and
      `card_type: "retirement"`. **Every one of these field names is load-
      bearing** — checked directly against
      `VoiceCalibrationReviewController#apply_card!` and
      `PipelineJob#build_result_payload`, both already built and unchanged
      by this design: `apply_card!` reads `card["heading"]`,
      `card["chapter_ref"]`, `card["quote"]`, `card["what_it_demonstrates"]`,
      `card["wrong_version"]`, `card["rule"]` for `"new_pattern"` cards and
      `card["passage_id"]` (populated later, see below) for
      `"retirement"` cards; a renamed or missing key silently breaks the
      review UI rather than raising, since both are plain hash reads with
      no schema validation.
    - **Return contract:** `[JSON.generate({cards: cards}), stderr,
      success?]` — matches `calibrate-voice.py`'s final `print(json.dumps(...))`
      exactly, since `PipelineJob#build_result_payload`'s existing
      `voice_calibration?` branch already does `JSON.parse(stdout)`, enriches
      each `"retirement"` card with `passage_id`/`quote` by looking up the
      matching `VoiceCalibrationPassage` (via `normalize_heading`,
      already built, already handles the "Passage N — " prefix mismatch
      between the model's heading citation and some backfilled DB rows),
      and re-serializes. **This enrichment logic is untouched and out of
      scope** — `Pipeline::Ruby::VoiceCalibration` only needs to produce
      the same `cards` shape `calibrate-voice.py` produces before that
      enrichment step runs; `PipelineJob` does the rest exactly as it does
      for the Python path today, with no branch on which implementation
      produced the stdout.
    - **Progress reporting:** same two-checkpoint pattern as
      `post_translation_review` above.
  - **Commit layer — `PostTranslationReviewController` and
    `BibleReviewWriter`, new Rails-layer scope beyond the two
    `Pipeline::Ruby::*` orchestrators above.** This is where every
    robustness/security item from the review pass actually lives, per the
    "single trusted boundary" reasoning stated earlier.
    - **`PostTranslationReviewController`** — structurally parallel to
      `VoiceCalibrationReviewController`'s `show`/`update`/`commit`
      actions (most recent completed `post_translation_review` job with a
      non-empty `cards` payload; per-card decision update — `accepted`,
      `accepted_revised`, `skipped` — persisted back into
      `result_payload`; `commit` iterates accepted cards and delegates
      each to the writer), written per the "target shared abstraction"
      note above so its generic mechanics don't have to be rewritten if
      that abstraction is extracted later. `show` additionally surfaces
      the staleness signal (below) to the reviewer before they decide.
    - **`BibleReviewWriter`** — the sole place that decides *what* bible-file
      mutation a card requires, for this job type. One write per accepted
      card. **Amended (see the R6 section below, which this note
      cross-references rather than duplicates): the actual locking,
      fresh-read, and atomic-write mechanics do not live in
      `BibleReviewWriter` itself.** They live in `Pipeline::BibleFileEditor`
      — a shared, bible-domain-agnostic primitive introduced by R6, because
      R6's `PrereadBibleWriter` needs the exact same hardening and R6 was
      designed after recognizing that two independent implementations of
      "lock → fresh-read → revalidate → atomic write" would be exactly the
      kind of duplication this document already warns against elsewhere
      ("a third implementation reinventing or forgetting them" — see the
      "single trusted boundary" reasoning above, now realized as a literal
      shared class rather than just a shared expectation). `BibleReviewWriter`
      itself owns only card semantics and calls into the primitive:
      1. For a `proposed_edit` card: `BibleFileEditor#replace(file, current:,
         proposed:)`. The primitive locks the file, re-reads it fresh under
         the lock (not the copy read at proposal-generation time — this is
         what actually closes the TOCTOU gap, not a whole-file hash
         comparison, since re-running the *specific* check each card
         depends on avoids false-positive aborts on unrelated concurrent
         edits elsewhere in the same file), and requires the `current` text
         to match **exactly once** in that fresh read — zero and multiple
         matches are both skips, with distinguishable reasons
         (`:skipped_not_found`/`:skipped_ambiguous`) rather than one
         collapsed bucket.
      2. For a `new_entry` or `story_update` card: `BibleFileEditor#append_block(file)
         { |fresh_content| ... }`. `BibleReviewWriter` supplies the block —
         heading-key dedup for `new_entry`, exact-text dedup for
         `story_update` (closes the idempotency gap flagged in review: a
         story update whose exact text already exists in `story.md` is
         skipped, same lexical-not-semantic limitation heading-key dedup
         already accepts) — evaluated against the fresh read the primitive
         hands it, never the proposal-generation-time snapshot. The block
         returns either the merged content to write or a sentinel meaning
         "duplicate, skip."
      3. Either call locks only the one file it targets (per-card, per-file
         — never all 5 preemptively; see R6's locking-scope reasoning,
         which applies identically here), held only for the
         lock→fresh-read→decide→write sequence, **not** across the
         (already-finished, minutes-old) LLM call — concurrent review
         commits against different files never contend, and even same-file
         commits only serialize for the duration of one small
         read-modify-write, not a whole review cycle.
      4. The primitive writes to a sibling `.tmp` path and `File.rename`s it
         into place — atomic on the same filesystem, so a mid-write crash
         (process killed, `:killed`/OOM-traceable per
         `Pipeline::ClaudeCode::Result`'s existing taxonomy) can never leave
         a truncated bible file on disk — then releases the lock.
      Each card's outcome (applied / skipped-not-found /
      skipped-ambiguous / skipped-duplicate) is recorded back onto the
      job so the reviewer sees what actually happened, not just what they
      clicked.
    - **Staleness handling, formalized as three cooperating layers, not
      one mechanism — a distinction the "warn vs. auto-revalidate vs.
      reject" framing from review maps onto directly:**
      - **Warn** (advisory, UI-layer): `show` recomputes each of the 5
        bible files' SHA-256 and compares against the `bible_revision`
        map stored at generation time (above). A mismatch surfaces a
        banner — *"the bible has changed since these proposals were
        generated"* — before the reviewer decides anything. Cheap, purely
        informational, never blocks.
      - **Auto-revalidate** (enforcing, writer-layer): step 2 above — the
        live re-check against a freshly-read file under the lock. This is
        what actually protects data integrity regardless of whether the
        reviewer heeded the warning; even an ignored-warning Accept click
        can only succeed if the specific thing that card depends on is
        still true.
      - **Reject** — scoped to the individual card that fails
        auto-revalidation, not the whole commit batch. A commit accepting
        12 cards where one has gone stale during the review window still
        applies the other 11; the stale one is reported back as a skip
        with its specific reason, matching this document's general
        preference elsewhere (R4's partial-chapter-failure policy) for
        partial success over all-or-nothing.
      **Not extended to `voice_calibration` in this pass** —
      `VoiceCalibrationReviewController`/`VoiceCalibrationDocWriter` are
      already shipped and structurally exposed to the same async-review
      staleness gap, but retrofitting them is out of scope here (same
      "don't touch already-shipped code" boundary the hardening decision
      already drew). Named as a natural candidate once the shared
      abstraction above is actually extracted — the fingerprint/warn/
      revalidate pattern would apply to `voice_calibration`'s commit path
      unchanged, since it doesn't depend on anything bible-specific.
    - **Cross-language locking gap, found while designing the lock
      sequence above, not assumed away — narrowed by R6, not yet fully
      closed.** `flock`-based locking only protects against writers that
      also take the lock. Checked against the current codebase:
      `preread`/`bible_build` write to these same 5 files via
      `src/preread/bible_writer.py`, which does not lock today. **R6 (below)
      is now designed** — it ports `preread`/`bible_build` onto the same
      `Pipeline::BibleFileEditor` primitive `BibleReviewWriter` uses here, so
      once R6 is *built and flipped to `ruby`* via `PIPELINE_IMPL_PREREAD`/
      `PIPELINE_IMPL_BIBLE_BUILD`, every Ruby-side writer of these 5 files
      shares one lock discipline. Until then — and regardless of R6, for as
      long as `PIPELINE_IMPL_POST_TRANSLATION_REVIEW` itself stays
      `"python"` — the gap is real: `BibleReviewWriter`'s locking only
      closes the Ruby-vs-Ruby race, not Ruby-vs-still-Python. Since
      `flock`/`fcntl.flock` are both thin wrappers over the same `flock(2)`
      syscall on Linux, cross-language locking on the same lockfile path
      would work if both sides took it — but adding that to
      `src/preread/bible_writer.py` (or to `src/bible_review/bible_writer.py`,
      `run_review.py`'s own still-Python writer) is Python-side work outside
      this Ruby-focused design. **Not resolved here:** whether to add
      symmetric locking to either Python writer now (small, isolated change)
      or accept the residual lost-update risk until both R5 and R6 are
      built and their respective `PIPELINE_IMPL_*` flags flipped. Flagged
      for a decision, not silently accepted or silently fixed.
  - **Error handling — single-call, not a batch, so R4's recoverable/fatal
    split doesn't apply as a branching policy here.** Both job types make
    exactly one `Pipeline::ClaudeCode` call; there's no "continue to the
    next chapter" decision to make. `Pipeline::ClaudeCode::Result`'s
    existing 6-category `error_category` (R1) is still the failure signal —
    on any non-nil category, both classes return
    `["", "#{result.error_category}: #{result.error_message}", false]`,
    letting `PipelineJob#perform`'s existing failure path (mark the job
    `failed`, join `stdout`/`stderr` into `result_payload`) handle it
    unchanged. No new error taxonomy, no new failure-status columns.
  - **Model/budget configuration — a real open question, not silently
    resolved here.** `TranslationConfig` (R1, already built) exposes exactly
    one `translation_model`/`translation_max_budget_usd` pair, read once
    from `TRANSLATION_MODEL`/`TRANSLATION_MAX_BUDGET_USD`. Python's
    `config.py` used a different model per call site (`SONNET_MODEL` for
    `run_review.py`, before this design moved it off `src/agent.py`
    entirely) and a `TRANSLATION_MAX_BUDGET_USD` that was never applied to
    review/calibration calls at all (only `claude_code_agent.py`'s
    translation path read it). Two honest options, **not decided here**:
    **(a)** reuse `TranslationConfig#translation_model`/
    `#translation_max_budget_usd` as-is for both new call sites — simplest,
    but couples review/calibration budget to whatever translation's budget
    is tuned to, even though a single-call review is a very different cost
    shape than a multi-chapter translation batch; **(b)** add new
    `REVIEW_MODEL`/`REVIEW_MAX_BUDGET_USD`-shaped fields to
    `TranslationConfig`, mirroring `config.py`'s original per-call-site
    granularity. Named here as a decision for whoever builds R5, same
    "don't invent a number" discipline R4's design already applied to its
    own declined concurrency-cap suggestion — no default is recommended in
    this document.
- **Acceptance criteria:**
  - `Pipeline::Ruby::PostTranslationReview.call(job)` and
    `Pipeline::Ruby::VoiceCalibration.call(job)` both return
    `[JSON.generate({cards: [...], ...}), stderr, success?]`, matching
    `PipelineDispatcher#dispatch_ruby`'s existing pass-through contract —
    verified against the real call site, not assumed. Both classes emit
    the same kind of payload; neither returns a plain-text summary.
  - **Neither class writes to disk.** Both read as orchestrators (read →
    build prompt → call `Pipeline::ClaudeCode` → parse → emit cards), with
    no bible-parsing, MCP, subprocess, or filesystem-write logic
    reimplemented inline — a stricter criterion than R4's, since these two
    don't reach the write path at all, not just avoid reimplementing it.
  - Chapter selection comes from `job.chapter_start` for both — no CLI
    argument parsing, "latest translated chapter" resolution, or novel-name
    disambiguation is ported; those exist only because both Python scripts
    are also standalone CLI tools.
  - Neither class builds an `mcp_config` or spawns `bin/mcp_skill_bridge` —
    verified against both Python system prompts containing no tool-use
    instructions, not assumed by analogy to R4.
  - Both classes call `Pipeline::ClaudeCode`, not a ported `src/agent.py` —
    a deliberate, user-confirmed departure from `run_review.py`'s current
    production behavior (which stays on the local Ollama backend today,
    per `docs/DECISIONS.md`'s 2026-07-21 entry), extending the same
    quality-ceiling reasoning that already moved `calibrate-voice.py` off
    local rather than reversing R1's local-backend-port deferral.
  - `Pipeline::PromptUtils.section`/`.is_empty` exists as a module shared
    with (not duplicated from) R4's translation prompt builder — whichever
    of R4/R5 is built first creates it.
  - A Ruby port of `bible_utils.py`'s `heading_key`/`extract_heading_keys`
    exists and is verified against the same Korean-parenthetical examples
    Python's own docstring uses — not derived from or redirected to
    `BibleMarkdownParser`, which serves a different purpose. Used only by
    `BibleReviewWriter`'s live re-validation (below), not by either
    `Pipeline::Ruby::*` orchestrator.
  - `post_translation_review`'s assembled `system_prompt`/`user_message`
    and `voice_calibration`'s assembled `system_prompt`/`user_message`
    byte-match Python's builder output for a representative sample of real
    chapters, checked before ever comparing model output — same discipline
    R4's acceptance criteria already state for its own prompt builder.
  - `post_translation_review`'s cards, proposed edits, and story updates
    are represented as `Data.define` value objects
    (`NewBibleEntry`/`ProposedBibleEdit`/`StoryUpdate`) from parse time
    onward, not raw hashes — serialized to the wire-format card hash only
    at the JSON-emission boundary.
    - **All three card types — new entries included — require human
      review before anything is written to disk.** No mutation type for
      `post_translation_review` auto-applies; this is a deliberate,
      user-confirmed reversal of `run_review.py`'s current production
      behavior (which auto-applies edits and story updates, and writes new
      entries immediately), not a parity port. Verified consistent with
      `voice_calibration`, which already gates its `new_pattern` cards the
      same way it gates `retirement` cards.
  - A response exceeding the configured size/count/field-length bounds
    (starting point: 200 KB total, 50 cards, 5,000 characters per field)
    fails the whole call before any card is constructed — checked
    immediately after the API response returns, not deferred to the
    writer.
  - A response missing its top-level section markers entirely fails the
    call outright (distinct from "sections present but empty," which is a
    legitimate "nothing to report" outcome) — the parser does not treat
    the two as equivalent. Individual malformed blocks within a present
    section are rejected and do not become cards, rather than being
    silently absorbed into an adjacent entry.
  - `Pipeline::Ruby::PostTranslationReview` captures a SHA-256 of each of
    the 5 relevant bible files at proposal-generation time and includes it
    as a `bible_revision` map alongside `cards` in its emitted JSON.
  - A new `PostTranslationReviewController` exists, structurally parallel
    to `VoiceCalibrationReviewController` (`show`/`update`/`commit`,
    per-card decision persisted into `result_payload`), named by job type
    rather than domain (`PostTranslationReviewController`, not
    `BibleReviewController`) and written so its generic show/update
    mechanics could later be lifted into a shared reviewable-job layer
    without a rename — that extraction itself is explicitly **not** built
    in this pass. `show` surfaces a staleness warning when any of the 5
    files' current SHA-256 differs from the `bible_revision` captured at
    generation time.
  - `BibleReviewWriter` is the only code path that decides *what* mutation
    a card requires for `bible/{characters,locations,terminology,cultural_phrases,story}.md`,
    but performs **no file I/O, locking, or atomic-write logic itself** —
    every write goes through `Pipeline::BibleFileEditor` (shared with R6,
    below), via `replace(file, current:, proposed:)` for `proposed_edit`
    cards or `append_block(file) { ... }` for `new_entry`/`story_update`
    cards. Through that primitive, every write:
    - acquires a per-file `flock(LOCK_EX)` (one file per card — never all 5
      preemptively), held only for the re-read/validate/write/rename
      sequence, never across the (already-finished) LLM call;
    - re-reads the target file fresh under the lock and re-validates the
      specific thing the card depends on against that fresh read — not
      against the file as it stood at proposal-generation time — before
      writing anything ("lock-then-revalidate," not a retry/version-check
      scheme);
    - requires a `proposed_edit`'s `current` text to match **exactly
      once**; zero and multiple matches are both skips, with
      distinguishable reasons recorded per card, not collapsed into one
      bucket;
    - deduplicates `new_entry` cards by canonical heading key and
      `story_update` cards by exact text match against the freshly-read
      file (dedup logic supplied by `BibleReviewWriter`'s `append_block`
      callback, not by the primitive — the primitive stays bible-domain-
      agnostic) — a rerun against an unchanged bible, or a stale card whose
      content already landed via another path, produces zero duplicates;
    - writes to a sibling `.tmp` path and `File.rename`s it into place —
      never a direct in-place write — so a mid-write crash can never leave
      a truncated bible file on disk;
    - on a commit accepting multiple cards, one card failing
      re-validation skips only that card and reports why — it does not
      abort the rest of the batch.
  - The staleness fingerprint (`show`'s warning) and the primitive's live
    re-validation are named as two distinct, cooperating layers — advisory
    warning vs. enforcing check — not one mechanism standing in for the
    other; neither is described as sufficient on its own.
  - The cross-language locking gap against still-Python
    `preread`/`bible_build` writers (which don't `flock` today) is named
    as a real, verified, open finding, narrowed but not fully closed by R6
    (below) — not silently assumed closed by `BibleReviewWriter`'s own
    locking, and not silently patched into `src/preread/bible_writer.py` by
    this document either.
  - Extending the staleness-fingerprint/warn/revalidate pattern to
    `voice_calibration`'s existing (shipped, unchanged) review/commit path
    is named as a future candidate once the shared abstraction is
    extracted — not attempted in this pass.
  - `Pipeline::Ruby::VoiceCalibration` performs no file writes of any kind
    — verified this matches `calibrate-voice.py`'s own behavior, not an
    accidental scope gap. All actual voice-calibration file writes remain
    in the already-shipped `VoiceCalibrationReviewController`/
    `VoiceCalibrationDocWriter`, untouched by this design.
  - The `cards` JSON emitted by `Pipeline::Ruby::VoiceCalibration` uses the
    exact field names `VoiceCalibrationReviewController#apply_card!` and
    `PipelineJob#build_result_payload` already read
    (`id`, `card_type`, `heading`, `chapter_ref`, `quote`,
    `what_it_demonstrates`, `wrong_version`, `rule` for `"new_pattern"`;
    `id`, `card_type`, `heading`, `reason` for `"retirement"`) — verified
    against those two already-shipped call sites, not assumed from
    `calibrate-voice.py`'s shape alone.
  - `PipelineJob#build_result_payload`'s existing retirement-enrichment
    logic (`passage_id`/`quote` lookup via `normalize_heading`) is not
    duplicated or modified by this design — it already works identically
    regardless of which `PipelineImplementation` produced the stdout. No
    change to `PipelineJob` is needed for `post_translation_review` either
    — its `unless job.voice_calibration?` fallthrough already stores raw
    JSON stdout unchanged, verified sufficient since bible cards need no
    equivalent server-side enrichment.
  - Both job types report progress via the same
    `/tmp/hawk_job_#{job.id}.progress` file-based protocol `PipelineJob`'s
    polling thread already reads — two checkpoints (before/after the API
    call), not a new mechanism.
  - On any `Pipeline::ClaudeCode::Result` failure (`error_category` non-nil),
    both classes return `["", "category: message", false]` and let
    `PipelineJob#perform`'s existing failure path handle job status —
    no new error taxonomy or batch fail-fast/continue policy, since neither
    job type makes more than one API call.
  - Whether review/calibration calls reuse `TranslationConfig`'s existing
    `translation_model`/`translation_max_budget_usd` or get their own
    dedicated config fields is named as an open decision for R5's build,
    not silently resolved by this document.
  - **Test coverage named as required for the eventual build** (design-only
    phase, so none of this is written yet, same as every other criterion
    here): duplicate headings, malformed parser sections, missing required
    fields, zero-byte and oversized responses, duplicate `current` text
    across proposed edits, concurrent writers to the same bible file,
    an interrupted atomic write (crash between `.tmp` write and rename),
    rerunning an identical review twice, invalid UTF-8 in model output,
    Windows vs. Unix line endings, markdown content with embedded `###`
    sequences that could be mistaken for section/file-label headers, and
    extremely long field values at and beyond the configured cap.
  - No Ruby implementation code is written as part of this section — a
    separate, later pass, same discipline as R0–R4.

---

## R6 — `preread` and `bible_build` orchestration

**Status: designed 2026-07-25, built and spec-tested 2026-07-25 (same
day — see the build note near the top of this document for the file list
and the one deliberate scope trim: Python's inter-batch `time.sleep(1)`
wasn't ported).** Scoped as the first
of R6's three originally-bundled pieces (preread, formatter, OCR) — the user
picked `preread`/`bible_build` specifically because, unlike the formatter
(`clean_chapter.py`/`FormatKoreanChapterJob`) and OCR (`ocr_chapter.py`/
`OcrChapterJob`), it fits directly into the `TranslationJob` →
`PipelineDispatcher` → `PIPELINE_IMPL_*` → `Pipeline::Ruby::*` machinery R1–R5
already built. The formatter and OCR are structurally different — both are
triggered by chapter upload via plain `ActiveJob` classes, not
`TranslationJob`s, with no `PipelineDispatcher` routing and no
`PIPELINE_IMPL_*` toggle today — and remain unscheduled, summary-level only.
This section was reviewed and revised once before being written up here, same
process R4/R5 went through: the review escalated from a narrower writer-
hardening critique into the architectural finding that R6's writer and R5's
`BibleReviewWriter` (above) should share one locking/atomic-write primitive
rather than duplicate it — see `Pipeline::BibleFileEditor` below, which this
section introduces and R5's `BibleReviewWriter` section (above) has already
been amended to use.

- **Goal:** Replace `Pipeline::Ruby::Preread.call(job)` and
  `Pipeline::Ruby::BibleBuild.call(job)`'s `NotImplementedError` stubs with a
  shared batch-loop orchestrator, ported from
  `src/preread/{runner,prompt_builder,response_parser,bible_reader,bible_writer}.py`
  and `src/bible_utils.py`/`src/prompt_utils.py` (both already required by
  R5 — reused here, not duplicated).
- **`bible_build` is `preread` with a different chapter-discovery source, not
  a separate script — verified, not assumed.** `run_bible_build.py` calls
  the exact same `src.preread.runner.run_preread()` as `run_preread.py`; the
  only difference is which chapters get selected before the batch loop
  starts (`find_all_korean_chapters` for `bible_build` — any chapter with a
  Korean source file, translated or not — vs. `find_untranslated_chapters`
  for `preread` — Korean source present, no translated `.txt` yet). So this
  section designs **one shared Ruby orchestrator**, parameterized by a
  chapter-discovery predicate, called by two thin public classes
  (`Pipeline::Ruby::Preread`, `Pipeline::Ruby::BibleBuild`) rather than two
  independent ports — mirroring Python's own "one runner, two callers" shape
  exactly.
- **Real, currently-live asymmetries between the two job types, checked
  against `PipelineDispatcher`/`PipelineJob` rather than inferred from the
  Python side, that the shared orchestrator must preserve rather than
  quietly unify:**
  - `PipelineDispatcher#run_preread` hardcodes `--batch-size 2`;
    `#run_bible_build` passes no `--batch-size` flag at all, so it runs at
    Python's own default of 5. Two different tuned values in production
    today — batch size is a call-site argument to the shared orchestrator,
    never a constant hardcoded inside it.
  - `PipelineJob#update_chapters`'s `case` only has branches for
    `["preread", "start"|"success"|"failure"]`
    (`untranslated`/`preread_failed` → `prereading` → `preread`/
    `preread_failed`). `bible_build` matches no branch — it never touches
    chapter status, since it deliberately operates on already-translated
    chapters. Likewise `TranslationJob#reset_prereading_chapters!`
    (`cancel!`/`mark_dead!`) is gated `return unless preread?` — cancelling
    a `bible_build` job resets no chapter status either. This design does
    not touch `PipelineJob`/`TranslationJob` at all; both keep dispatching
    on `job_type` exactly as they do today.
- **Chapter-range filtering is real, still-exercised safety-net behavior —
  not out-of-scope CLI convenience the way R4/R5's chapter-selection
  parsing was correctly excluded.** `TranslationJobsController` places no
  server-side constraint on a `preread` job's `chapter_start..chapter_end`
  beyond "start ≤ end, start ≥ 1" (`TranslationJob#chapter_range_valid`) —
  nothing stops a range that includes an already-translated chapter. Today,
  Python's `find_untranslated_chapters`/`find_all_korean_chapters` plus
  `parse_chapter_selection`'s `_filter_and_warn` silently drop out-of-scope
  chapter numbers from the requested range before batching even starts.
  Unlike R4/R5 (where Rails already supplies the exact selection and CLI
  parsing was rightly out of scope), **this filter is a live behavioral
  guarantee, not CLI convenience**: a `preread` job spanning a range where
  chapter 5 got translated in the meantime must skip re-prereading it; a
  `bible_build` job over the same range must not skip it. The Ruby port
  needs an equivalent filter step — the same per-job-type discovery
  predicate named above, applied against `job.chapter_start..job.chapter_end`
  — not the literal range handed to the batch loop unfiltered.
- **The human-review layer already exists, is already shipped, and settles
  the auto-apply question rather than reopening it — this is a verified
  constraint, not a design choice up for reconsideration.**
  `PrereadReviewController` + `BibleMarkdownParser#pending_entries` +
  `BibleImportController` + a `preread_dismiss` action already provide
  preread's review/accept/dismiss flow, and they work nothing like R5's
  card-based pattern: they **live-diff the current bible markdown files
  against `BibleCharacter`/`BibleLocation`/`BibleTerminology`/
  `BibleCulturalPhrase`/`BibleStoryEntry` DB records** (skipping anything
  whose `"category:korean_key"` appears in `Novel#preread_dismissed_keys`,
  a JSON array `PrereadDismissController` appends to), not a stored
  `TranslationJob.cards`/`result_payload` at all. This flow depends on the
  markdown files actually being written immediately, exactly like Python's
  `bible_writer.py` does today — gating writes behind a new pre-disk review
  step (R5's pattern for `post_translation_review`) would break or
  duplicate this already-working UI. So `Pipeline::Ruby::Preread`/
  `BibleBuild` keep writing to markdown directly and immediately, same as
  today.
- **Hardening still applies — to the write mechanics themselves, not to
  gating writes behind approval, and it cannot be deferred to an
  async-commit step the way R5's `BibleReviewWriter` is.**
  `src/preread/bible_writer.py` is exactly the writer R5's own section
  (above) flags as the cross-language locking gap. Porting it to Ruby is
  the moment to add real locking and atomic writes — but the write **must
  run synchronously inside the batch loop**, not behind a separate commit
  step: `run_preread` re-reads bible files fresh before every batch
  specifically so the previous batch's writes are visible to the next
  prompt (cross-batch dedup depends on it). One real, if incidental and
  fragile, mitigation already exists today: `PipelineJob` is a single
  `ActiveJob` class for every job type (`docs/DECISIONS.md`, 2026-03), and
  its `limits_concurrency to: 1` is gated only on whether `LLM_BASE_URL`
  resolves to a local/private host — not scoped by job type or by which
  backend an individual job type picked. So as long as `LLM_BASE_URL` stays
  at its local default, every `TranslationJob` (preread, bible_build,
  translate_batch, review, calibration — Python or Ruby) already runs
  strictly one-at-a-time, which prevents the concurrent-writer race in
  practice today. This is named here as a fragile, incidental protection —
  an env var most people would eventually change once nothing actually
  depends on local Ollama, unaware it's silently also serializing every
  pipeline job — a reason real locking is still worth building, not a
  reason to skip it. Closing the cross-language half of the gap needs both
  R5 and this section built, and `PIPELINE_IMPL_POST_TRANSLATION_REVIEW`
  actually flipped to `"ruby"` (see the amended note in R5's section,
  above) — named here, not solved by this design alone.
- **No `--mcp-config`/bridge needed** — verified `src/preread/prompt_builder.py`'s
  full system prompt contains no tool-use instructions, same shape as R5's
  finding for `bible_review`/`voice_calibration`.
- **Backend is currently unconditionally local, same deferred-local-port
  question R4/R5 hit.** `run_preread.py`/`run_bible_build.py` call
  `src.agent.call`/`make_client()` directly, never `get_backend(...)` —
  grouped among the "remaining 7" local-only scripts as of
  `docs/DECISIONS.md`'s 2026-07-21 entry, the same group `run_review.py` was
  in before R5 moved it. **No preread-specific quality complaint is on
  record** (unlike `voice_calibration`'s documented generic-output problem),
  so this is named as an open decision, not a foregone conclusion — but
  **recommended**: move onto `Pipeline::ClaudeCode`, extending R5's
  precedent, rather than reopening the "build a Ruby local/Ollama tool-loop"
  question R1 already deferred indefinitely.
- **Model/budget configuration is the same open question R5 already
  declined to resolve, recurring a third time.** Python's preread/
  bible_build use `SONNET_MODEL` (distinct from `translate.py`'s
  `OPUS_MODEL`); Ruby's `TranslationConfig` exposes exactly one
  `translation_model`/`translation_max_budget_usd` pair. Named here as
  still-open, not decided — same as R5.
- **Design:**
  - **Shared orchestrator, one class not two** — e.g.
    `Pipeline::Ruby::PrereadRunner` (private, shared), called by both
    `Pipeline::Ruby::Preread.call(job)` and
    `Pipeline::Ruby::BibleBuild.call(job)`, each supplying its own
    chapter-discovery predicate and batch size. Public return contract for
    both: `[stdout, stderr, success?]` per `PipelineDispatcher#dispatch_ruby`'s
    existing pass-through (verified against the real call site) — plain
    progress/log text is fine here (unlike R5's cards-JSON contract), since
    nothing downstream parses preread/bible_build's `result_payload` as
    structured data; `PipelineJob#build_result_payload`'s
    `unless job.voice_calibration?` branch already stores raw stdout
    unchanged for every other job type.
  - **Batch loop, per batch:** re-read the 5 bible files + `novel_info.md`
    fresh → build system/user prompt (`Pipeline::PromptUtils.section`,
    shared with R4/R5) → `Pipeline::ClaudeCode.call(mcp_config: nil)` →
    parse the 5-section response (`=== CHARACTERS ===` etc., "NOTHING TO
    ADD" → empty, same fail-closed-on-missing-markers discipline R5
    established) → hand the parsed batch to `Pipeline::PrereadBibleWriter`
    (below) → advance `/tmp/hawk_job_#{job.id}.progress`
    (`batch_index / total_batches * 100`, same file-based protocol as
    R4/R5) → continue to the next batch.
  - **Error handling:** same `Pipeline::ClaudeCode::Result` 6-category
    taxonomy as R1/R5; on any batch's API-call failure, stop the loop —
    don't continue to remaining batches, since a fresh-bible-state read for
    batch N+1 is meaningless once batch N's own call already failed — and
    return failure. Batches already written before the failing one keep
    their writes (each batch's write already landed atomically before the
    next batch started, so there is no partial-batch corruption to roll
    back, only "fewer batches completed than requested," surfaced via
    `stderr`/job status the same as any other failure).
  - **Three layers, not two — a shared mutation primitive underneath both
    this section's writer and R5's `BibleReviewWriter`, not two
    independently-hardened writer classes that happen to look alike.** R5's
    own section (above) already warned about exactly this failure mode —
    "a third implementation reinventing (or forgetting)" the hardening.
    Since neither writer was built at the time this was designed, this is
    the point at which that duplication was actually avoided, not just
    warned about — R5's section above has already been amended accordingly:

    | layer | owns | example |
    |---|---|---|
    | `Pipeline::BibleFileEditor` (new, shared) | lock → fresh-read → mechanical validate → atomic write. **No bible-domain knowledge** — doesn't know what a character, term, or card is. | `replace(file, current:, proposed:)`, `append_block(file) { \|fresh_content\| ... }` |
    | `Pipeline::PrereadBibleWriter` (this section) | batch parsing, grouping parsed entries by target file, heading-key dedup logic, iterating touched files | calls `BibleFileEditor#append_block` per file |
    | `BibleReviewWriter` (R5, amended above) | card semantics, one-card-at-a-time application, its own dedup/staleness logic | calls `BibleFileEditor#replace`/`#append_block` per accepted card |

    Neither writer touches `File`, `flock`, or `.tmp`/`rename` directly —
    that correctness-critical code lives in exactly one place.
    - **`BibleFileEditor#replace(file, current:, proposed:)`** — lock,
      fresh read, count exact occurrences of `current`; exactly one →
      atomic write with `proposed` substituted, return `:applied`; zero →
      `:skipped_not_found`; more than one → `:skipped_ambiguous`. Purely
      mechanical text matching — no bible-domain knowledge needed to count
      substring occurrences — so it belongs in the primitive, and it's a
      verbatim extraction of R5's already-designed `proposed_edit`
      semantics, not new behavior. (`PrereadBibleWriter` itself has no
      current use for `replace` today — preread only ever appends — but the
      primitive exposes it because R5's writer needs it, and duplicating
      the primitive per call site is exactly what this design avoids.)
    - **`BibleFileEditor#append_block(file) { |fresh_content| ... }`** —
      lock, fresh read, yield the freshly-read content to a caller-supplied
      block. The block decides — using domain logic it owns, never the
      primitive — whether anything is new (`heading_key`-based dedup for
      this section, story-update exact-text dedup for R5), and returns
      either the merged full content to write or a sentinel meaning
      "nothing changed, skip." The primitive performs the atomic write only
      if told to.
    - **Keep the primitive mechanics-only, not domain-aware.** Good:
      replacing text, appending a block, writing atomically. Not the
      primitive's job: understanding characters, terminology, story
      entries, or review cards — that stays in `PrereadBibleWriter`/
      `BibleReviewWriter`, where business rules belong.
    - **Write sequence, named "lock-then-revalidate," deliberately not
      "optimistic validation."** The earlier draft of this design borrowed
      language from optimistic concurrency control (read → work → compare
      version → retry), which isn't what this is — there is no retry loop
      or version check anywhere in this design. The actual sequence is a
      pessimistic critical section with a fresh read inside it: batch → LLM
      call → parse → (per touched file) lock → reload fresh → the caller's
      block validates/merges against that fresh read, never the
      batch-start snapshot → atomic write → release lock. The bible state
      read at the *top* of the batch loop (to build the prompt) and the
      state re-read *inside* `BibleFileEditor` (to merge into) are
      deliberately two different reads — the first is what the model saw,
      the second is authoritative for what gets written.
    - **Lock only the files a batch actually touches, not all 5
      preemptively — canonical ordering kept as a documented convention,
      not a fix for a live bug.** No writer anywhere in this codebase, R5's
      included, ever holds more than one bible-file lock at a time, so
      there is no current deadlock risk locking-all-5 would defend against
      — only unneeded contention. Documented verbatim, next to the
      primitive: *"Locks are acquired only for files the batch will modify.
      When multiple locks are needed, they are always acquired in
      canonical filename order. No current writer acquires locks in
      conflicting orders; this ordering is maintained as a preventative
      invariant rather than as a fix for an existing deadlock."*
    - **Transaction boundary is per-file, not per-batch — an intentional
      limitation, stated explicitly, not an oversight.** A batch's parsed
      response can touch multiple bible files; true cross-file atomicity
      (all land or none do) would need journal/two-phase-commit-style
      machinery, disproportionate for markdown files. Instead: for the
      files a batch touches, acquire their locks (canonical order),
      compute each file's merged content against its fresh read *before*
      renaming any of them, then rename back-to-back before releasing any
      lock. This narrows the inconsistency window (no crash mid-*compute*)
      but does not eliminate it — a crash between two renames still leaves
      one file updated and the other not. **Atomicity is guaranteed per
      file, best-effort-ordered across the touched files within one batch,
      not a cross-file transaction.**
    - Fail-closed parsing stays upstream, in the parser: missing section
      markers entirely → the whole batch fails before `PrereadBibleWriter`
      (or `BibleFileEditor`) is ever invoked, not silently-empty.
  - **Chapter-range filtering:** port the discovery-predicate + filter step
    (Python's `find_untranslated_chapters`/`find_all_korean_chapters` +
    `_filter_and_warn`) applied against `job.chapter_start..job.chapter_end`
    — real, still-exercised behavior per the finding above, not excluded
    the way CLI selection parsing was in R4/R5.
  - **Open, not decided in this pass** (named for whoever builds it, same
    discipline as R4/R5's declined decisions):
    - Backend: local vs. `Pipeline::ClaudeCode` (recommended:
      `Pipeline::ClaudeCode`, see finding above).
    - Model/budget: reuse `TranslationConfig#translation_model`/
      `#translation_max_budget_usd` vs. dedicated `PREREAD_MODEL`/
      `PREREAD_MAX_BUDGET_USD` fields.
    - Whether to add `flock` to the still-Python
      `src/bible_review/bible_writer.py` (and/or `src/preread/bible_writer.py`,
      until this section is built) now — small, isolated, closes the
      cross-language gap early — or accept the residual risk until both R5
      and this section are built and their `PIPELINE_IMPL_*` flags flipped.
- **Acceptance criteria:**
  - The shared orchestrator is verified against both dispatch call sites'
    actual argv construction — the batch-size asymmetry (2 for `preread`,
    Python's default of 5 for `bible_build`) is preserved, not unified into
    one constant.
  - Chapter-status side effects are unchanged: `update_chapters`/
    `reset_prereading_chapters!` remain keyed off `job_type` exactly as
    today (`bible_build` triggers neither), not touched by this design.
  - Assembled system/user prompts byte-match Python's builder output for
    real chapters, checked before ever comparing model output — same
    discipline R4/R5's acceptance criteria already state for their own
    prompt builders.
  - **`Pipeline::BibleFileEditor` is the sole code path in the whole app
    that touches `File`, `flock`, or `.tmp`-then-`rename` for any of the 5
    bible files.** Neither `PrereadBibleWriter` (this section) nor
    `BibleReviewWriter` (R5, amended) performs file I/O directly, and
    `BibleFileEditor` itself contains no bible-domain knowledge — no
    reference to characters, terminology, cards, or headings — verified by
    its spec suite needing no bible fixtures at all, just arbitrary text
    files.
  - Every `replace`/`append_block` call locks only the file(s) it targets
    (never all 5 preemptively) and, when a batch or commit needs more than
    one, acquires them in canonical filename order — documented as a
    preventative invariant, not a fix for a live deadlock.
  - Every merge/replace decision is computed against the fresh read taken
    *inside* the lock, never the snapshot read at batch-start or
    proposal-generation time — the "lock-then-revalidate" sequence, not
    "optimistic validation": no retry or version-check machinery exists or
    is implied anywhere in this design.
  - A batch touching multiple files computes every touched file's merged
    content before renaming any of them, then renames back-to-back before
    releasing locks — documented explicitly as per-file atomicity,
    best-effort-ordered across the touched files, not a cross-batch
    transaction.
  - A response missing top-level section markers entirely fails the batch
    before `PrereadBibleWriter` (or `BibleFileEditor`) is ever invoked —
    distinct from "sections present but empty," a legitimate "nothing to
    add" outcome.
  - `PrereadReviewController`/`BibleMarkdownParser`/`BibleImportController`
    continue to work unmodified against Ruby-written markdown files — no
    schema or format drift in what gets written to the 5 bible files.
  - Chapter-range filtering drops out-of-scope chapter numbers (already
    translated, for `preread`; missing a Korean source, for both) from
    `job.chapter_start..job.chapter_end` before batching, matching Python's
    `_filter_and_warn` behavior — verified against a chapter range that
    includes an already-translated chapter for `preread` specifically
    (must skip it) and the identical range for `bible_build` (must not).
  - Test coverage named as required for the eventual build (design-only
    phase, so none of this is written yet): concurrent batches within one
    job, a crash between two touched files' renames within one batch,
    duplicate headings across batches, the chapter-range-filtering case
    above, oversized/malformed responses, and — since `BibleFileEditor` is
    now shared infrastructure — standalone primitive-level specs
    independent of any bible semantics.
  - No Ruby implementation code is written as part of this section — a
    separate, later pass, same discipline as R0–R5.

---

**R0 is fully built (R0.3 skipped by decision). R1, R2, and R3 are fully
built and tested, in that order (R2's skill class was a prerequisite for
R3's adapter; R1's backend-seam code has no runtime dependency on either
but was built first per the original sequencing). R4 (`translate_batch`
orchestration), R5 (`post_translation_review` + `voice_calibration`
orchestration), and now R6 (`preread` + `bible_build` orchestration) are
all designed, none built.** What exists now: `TranslationConfig` +
`Pipeline::ClaudeCode` (R1), `Pipeline::Skill` +
`Pipeline::Skills::BibleLookup` (R2), and `Pipeline::Mcp::ServerContext` +
`Pipeline::Mcp::BibleLookupTool` + `bin/mcp_skill_bridge` (R3) — plus an
`unsetenv_others: true` fix and `stdin:` support added to R0.1's
`Pipeline::Subprocess` along the way (see R1's section above). None of
this is wired to an actual translation or review call yet: nothing in this
app today builds a `Pipeline::ClaudeCode` call for any purpose, and no job
type's `Pipeline::Ruby::*` stub has been touched — R4's design settles
`translate_batch`'s orchestration (prompt building, mcp_config
construction, the bridge's env, partial-failure policy); R5's design
settles `post_translation_review`'s and `voice_calibration`'s (both
simpler — no bridge involved for either, plus a deliberate backend-migration
decision); R6's design settles `preread`'s and `bible_build`'s (a shared
batch-loop orchestrator, plus the finding that both job types' human-review
UI already exists and depends on immediate, un-gated markdown writes,
unlike R5's deferred-to-review pattern). **R5 was revised twice during
review, before any code was written, and both its orchestrators converge on
the same shape: read → prompt → call → parse → emit review cards, with
neither writing to disk.** Persistence for `post_translation_review` moves
to a new, not-yet-built `PostTranslationReviewController` +
`BibleReviewWriter` pair (mirroring `voice_calibration`'s existing shipped
review/commit pattern). **R6 was itself revised once during review, and the
finding escalated into an amendment of R5's already-written design, not
just R6's own:** rather than `BibleReviewWriter` and R6's writer
independently implementing the same locking/fresh-read/atomic-write
hardening, both now sit on top of one new shared primitive,
`Pipeline::BibleFileEditor` (mechanics only — lock, fresh-read, `replace`/
`append_block`, atomic write — with zero bible-domain knowledge), introduced
by R6 and already reflected in R5's `BibleReviewWriter` section above. Every
hardening measure from both review passes now lives in that one primitive —
per-file locking (only the files actually touched, in canonical order, not
all 5 preemptively), live re-validation against a freshly-read file rather
than a stale snapshot ("lock-then-revalidate," not optimistic
concurrency), atomic `.tmp`-then-`rename` writes, and (for R5 specifically)
response size/count caps, fail-closed parsing, and a staleness fingerprint
distinguishing an advisory UI warning from the primitive's actual enforcing
check. A generic `ReviewCard`/reviewable-job/controller abstraction spanning
R5's two job types is still named as a future direction but deliberately not
built now — a narrower, lower-level thing than `BibleFileEditor`, which *is*
in scope and shared starting now. Cross-file atomicity within one R6 batch
(or one R5 commit touching multiple cards) is explicitly out of scope too:
the transaction boundary is per-file, best-effort-ordered across whatever
files a single batch/commit touches, not a cross-batch/cross-commit
transaction — stated as an intentional limitation, not an oversight. None of
R4, R5, or R6 writes code yet; building `Pipeline::Ruby::TranslateBatch`,
`Pipeline::Ruby::PostTranslationReview`, `Pipeline::Ruby::VoiceCalibration`,
`Pipeline::Ruby::Preread`/`BibleBuild`, `Pipeline::BibleFileEditor`, and (for
`post_translation_review`'s commit path) `PostTranslationReviewController` +
`BibleReviewWriter` against these designs is the next step — R4, R5, and R6
don't depend on each other for their *orchestrator* halves, though R5's and
R6's writer halves now share `BibleFileEditor`, so whichever of the two
lands first builds that primitive. The formatter (`clean_chapter.py`/
`FormatKoreanChapterJob`) and OCR (`ocr_chapter.py`/`OcrChapterJob`) —
originally bundled into "R6" in the summary-level artifact linked above —
remain unscheduled and summary-level only: both are triggered by chapter
upload via plain `ActiveJob` classes outside `PipelineDispatcher` entirely,
with no `PIPELINE_IMPL_*` toggle today, so porting either needs a new
migration mechanism invented from scratch rather than filling in an existing
stub. R7 (deleting the Python layer) also remains at summary level, not yet
given the same detailed treatment.

**Update 2026-07-25 (same day, later session): R6 built and spec-tested —
`Pipeline::Ruby::Preread`/`BibleBuild` are no longer stubs.** Built in
dependency order (each layer spec-first): `Pipeline::PromptUtils`,
`Pipeline::BibleUtils`, `Pipeline::BibleFileEditor` (exactly as designed
above — lock-then-revalidate via a sidecar `<file>.lock` path rather than
locking the bible file's own path directly, since a concurrent writer's
already-open file descriptor would otherwise keep pointing at the old inode
after another writer's `.tmp`-then-`rename` swaps a new one in; this
mechanic wasn't spelled out at the file-descriptor level in the design
above, so it's noted here for whoever builds R5's `BibleReviewWriter` next
against the same primitive), `Pipeline::Ruby::PrereadRunner::ChapterDiscovery`/
`PromptBuilder`/`ResponseParser` (nested under `PrereadRunner`, not a
`Pipeline::Ruby::Preread` module — `Pipeline::Ruby::Preread` is itself a
class, so it can't also be reopened as a namespace module; the design
doc's illustrative naming didn't hit this Ruby-specific constraint),
`Pipeline::PrereadBibleWriter`, then `Pipeline::Ruby::PrereadRunner` itself.
`ResponseParser` adds the fail-closed "zero section markers at all" check
the design calls for above — checked directly against
`src/preread/response_parser.py` and confirmed Python's own version doesn't
actually implement this distinction (its "missing sections" warning can
never fire, since the results dict is pre-populated with every key before
the check runs). `PromptBuilder`'s system-prompt output was verified
byte-for-byte against a live `python3 -c` invocation of the real
`src/preread/prompt_builder.py`, not hand-transcribed (fixtures under
`spec/fixtures/preread/`) — direct evidence for the acceptance criterion
above, not just a claim of compliance. One deliberate scope trim: Python's
inter-batch `time.sleep(1)` ("brief pause… to be kind to the API") wasn't
ported — not correctness-critical and not named in the acceptance criteria
above; trivial to add later if real rate-limit pressure shows up. Full
`bundle exec rspec` run afterward: 937 examples, 58 failures — the same
count and (checked, not just counted) the same failing specs as the
pre-existing known-red baseline (see [[hawk_translations_auth_deferred]]),
zero regressions from this build. Not yet committed to `main` — this
build, plus R4's and R5's still-uncommitted design-doc updates above, are
all sitting in the working tree together; commit boundaries are for
whoever's driving that session to decide, not assumed here.
