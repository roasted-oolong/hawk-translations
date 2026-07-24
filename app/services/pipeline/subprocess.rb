# ---------------------------------------------------------------------------
# Pipeline::Subprocess
#
# Timeout-safe, cancellable subprocess execution. Every subprocess fork this
# app makes (today: PipelineDispatcher's Python scripts; later: the `claude`
# CLI call, the MCP bridge) can go through this instead of re-solving
# timeout/signal correctness at each call site.
#
# `cmd`/`env` are fully built by the caller — this class never knows or
# cares whether it's running Python, the `claude` CLI, or an MCP server.
#
# Deliberately does not retry: it executes once and reports what happened.
# Retry policy varies per job type and belongs in the orchestration layer
# above this.
# ---------------------------------------------------------------------------
module Pipeline
  class Subprocess
    # Subprocess wait latency doesn't need sub-100ms precision, and a fixed
    # interval is one less thing to get wrong.
    POLL_INTERVAL = 0.075

    # Grace period between SIGTERM and SIGKILL when terminating a process
    # group — gives a well-behaved child a chance to exit on its own before
    # being forced.
    TERM_GRACE_PERIOD = 5.0

    Result = Struct.new(
      :status, :exit_code, :started_at, :finished_at, :command_name,
      :stdout, :stderr, :bytes_stdout, :bytes_stderr,
      keyword_init: true
    ) do
      # Derived convenience predicate, not the source of truth — status and
      # exit_code are the two axes that actually describe what happened.
      def success?
        status == :completed && exit_code == 0
      end

      def duration
        finished_at - started_at
      end
    end

    def self.run(cmd, env:, timeout:, name:, cancel_token: nil)
      new(cmd, env: env, timeout: timeout, name: name, cancel_token: cancel_token).run
    end

    def initialize(cmd, env:, timeout:, name:, cancel_token: nil)
      @cmd          = cmd
      @env          = env
      @timeout      = timeout
      @name         = name
      @cancel_token = cancel_token
    end

    def run
      started_at = Time.now
      out_r, out_w = IO.pipe
      err_r, err_w = IO.pipe
      out_r.binmode
      err_r.binmode

      pid = ::Process.spawn(@env, *@cmd, pgroup: true, out: out_w, err: err_w, in: File::NULL)
      out_w.close
      err_w.close

      out_thread = Thread.new { out_r.read }
      err_thread = Thread.new { err_r.read }

      outcome = wait_for(pid, started_at)

      stdout = out_thread.value.to_s.force_encoding("UTF-8")
      stderr = err_thread.value.to_s.force_encoding("UTF-8")

      result = build_result(outcome, started_at, Time.now, stdout, stderr)
      log(result)
      result
    ensure
      out_thread&.join
      err_thread&.join
      out_r.close unless out_r.closed?
      err_r.close unless err_r.closed?
    end

    private

    # Polls at a fixed interval until the process exits naturally, the
    # timeout elapses, or the cancel_token flips — killing the whole process
    # group (never just the top pid) on either non-natural path, since a
    # Python interpreter or the `claude` CLI may fork children of its own
    # that a top-pid-only signal would leave orphaned.
    def wait_for(pid, started_at)
      loop do
        finished_pid, process_status = ::Process.waitpid2(pid, ::Process::WNOHANG)
        return { status: :completed, exit_code: exit_code_for(process_status) } if finished_pid

        if @cancel_token&.cancelled?
          kill_group(pid)
          return { status: :cancelled, exit_code: nil }
        end

        if Time.now - started_at > @timeout
          kill_group(pid)
          return { status: :timed_out, exit_code: nil }
        end

        sleep POLL_INTERVAL
      end
    end

    # A process can exit via a signal it wasn't sent by us (e.g. the kernel
    # OOM-killer) while still being reaped on the natural-completion path.
    # exitstatus is nil in that case — report the shell-style 128+signal
    # convention instead, so :completed never pairs with a nil exit_code.
    def exit_code_for(process_status)
      process_status.exitstatus || (128 + process_status.termsig)
    end

    def kill_group(pid)
      ::Process.kill("TERM", -pid)
      deadline = Time.now + TERM_GRACE_PERIOD
      loop do
        finished_pid, = ::Process.waitpid2(pid, ::Process::WNOHANG)
        break if finished_pid
        break if Time.now > deadline
        sleep POLL_INTERVAL
      end
      ::Process.kill("KILL", -pid)
      ::Process.waitpid(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      # Already reaped/exited between the grace-period check and the kill —
      # the group is gone either way, nothing left to clean up.
    end

    def build_result(outcome, started_at, finished_at, stdout, stderr)
      Result.new(
        status:       outcome[:status],
        exit_code:    outcome[:exit_code],
        started_at:   started_at,
        finished_at:  finished_at,
        command_name: @name,
        stdout:       stdout,
        stderr:       stderr,
        bytes_stdout: stdout.bytesize,
        bytes_stderr: stderr.bytesize
      )
    end

    # Only command_name + numeric/status fields — never full cmd or env.
    # PipelineDispatcher forwards the entire parent ENV (including
    # RAILS_MASTER_KEY, DATABASE_URL) into every subprocess; this must not
    # make that worse by writing it to logs.
    def log(result)
      message = "[Pipeline::Subprocess] #{result.command_name} " \
                "status=#{result.status} exit_code=#{result.exit_code.inspect} " \
                "duration=#{result.duration.round(3)}s " \
                "bytes_stdout=#{result.bytes_stdout} bytes_stderr=#{result.bytes_stderr}"
      result.success? ? Rails.logger.info(message) : Rails.logger.error(message)
    end
  end
end
