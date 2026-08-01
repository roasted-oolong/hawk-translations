require "tempfile"
require "json"

# ---------------------------------------------------------------------------
# Pipeline::ClaudeCode
#
# Ruby port of claude_code_agent.py's call() — the "claude_code" translation
# backend. Shells out to the `claude` CLI in headless mode, authenticated
# through the user's Claude subscription (OAuth) rather than a metered
# ANTHROPIC_API_KEY. Knows nothing about prompts, novels, or chapters: given
# a system prompt, a user message, and an optional pre-built MCP config, it
# returns a Result — R4+'s job is building the prompt, not this class's.
#
# argv array only, never a shell string (matches Pipeline::Subprocess /
# PipelineDispatcher's existing discipline). CLAUDE_BIN is resolved to an
# absolute path once by TranslationConfig, before this class ever spawns
# anything; the child's env is an allowlist built additively from {}
# (HOME + MCP_CONNECTION_NONBLOCKING only) — never ENV.to_h forwarded, and
# PATH is never part of it, since Process.spawn given an absolute-path
# executable never re-searches PATH.
# ---------------------------------------------------------------------------
module Pipeline
  class ClaudeCode
    # Matches claude_code_agent.py's own _TIMEOUT_SECONDS.
    DEFAULT_TIMEOUT = 1200

    # error_category is nil on success. On failure it's one of the six
    # taxonomy buckets from docs/RAILS_REFACTOR_PLAN.md's R1 design:
    # :binary_not_found, :timeout, :cancelled, :unparseable_output,
    # :cli_failure (covers both nonzero exit and is_error: true — OAuth
    # session problems surface through this bucket too, same as Python's
    # ClaudeCodeError), :killed (exit_code 137 / SIGKILL — plausibly but not
    # certainly an OOM kill, same ambiguity Pipeline::Subprocess's own
    # 128+signal convention already carries).
    Result = Struct.new(:output, :error_category, :error_message, :raw, keyword_init: true) do
      def success?
        error_category.nil?
      end
    end

    def self.call(system_prompt:, user_message:, config: TranslationConfig.from_env,
                   mcp_config: nil, model: nil, timeout: DEFAULT_TIMEOUT, process_env: ENV)
      new(system_prompt: system_prompt, user_message: user_message, config: config,
          mcp_config: mcp_config, model: model, timeout: timeout, process_env: process_env).call
    end

    def initialize(system_prompt:, user_message:, config:, mcp_config:, model:, timeout:, process_env:)
      @system_prompt = system_prompt
      @user_message  = user_message
      @config        = config
      @mcp_config    = mcp_config
      @model         = model
      @timeout       = timeout
      @process_env   = process_env
    end

    def call
      prompt_file = write_system_prompt_file
      begin
        subprocess_result = Pipeline::Subprocess.run(
          argv(prompt_file.path),
          env:      allowlisted_env,
          timeout:  @timeout,
          name:     "claude_code",
          stdin:    @user_message
        )
      rescue Errno::ENOENT
        return Result.new(
          error_category: :binary_not_found,
          error_message:  "claude CLI binary not found at #{@config.claude_bin}"
        )
      ensure
        prompt_file.close!
      end

      interpret(subprocess_result)
    end

    private

    def write_system_prompt_file
      file = Tempfile.new([ "hawk-system-prompt-", ".md" ])
      file.write(@system_prompt)
      file.flush
      file
    end

    # Order mirrors claude_code_agent.py's cmd list, so the two
    # implementations stay easy to diff against each other.
    def argv(prompt_path)
      cmd = [
        @config.claude_bin,
        "-p",
        "--system-prompt-file", prompt_path,
        "--output-format", "json",
        "--model", @model || @config.translation_model,
        "--tools", ""
      ]
      cmd += [ "--strict-mcp-config", "--mcp-config", @mcp_config.to_json ] if @mcp_config
      cmd + [
        "--permission-mode", "bypassPermissions",
        "--no-session-persistence",
        "--max-budget-usd", @config.translation_max_budget_usd.to_s
      ]
    end

    # Built additively from {} — never a deny-list carved out of ENV.to_h,
    # which is one missed key away from leaking RAILS_MASTER_KEY,
    # DATABASE_URL, ANTHROPIC_API_KEY, or any *_SECRET/*_KEY/*_TOKEN.
    def allowlisted_env
      env = { "MCP_CONNECTION_NONBLOCKING" => "false" }
      env["HOME"] = @process_env["HOME"] if @process_env["HOME"]
      env
    end

    def interpret(result)
      case result.status
      when :timed_out
        return Result.new(error_category: :timeout,
                           error_message: "claude CLI call timed out after #{@timeout}s")
      when :cancelled
        return Result.new(error_category: :cancelled,
                           error_message: "claude CLI call was cancelled")
      end

      # Checked before attempting to parse stdout: a killed process's stdout
      # is typically empty/truncated, so this would otherwise misreport as
      # :unparseable_output and lose the more useful signal.
      if result.exit_code == 137
        return Result.new(error_category: :killed,
                           error_message: "claude CLI process was killed (exit_code 137, possible OOM)")
      end

      data = begin
        JSON.parse(result.stdout)
      rescue JSON::ParserError
        return Result.new(
          error_category: :unparseable_output,
          error_message:  "claude CLI returned unparseable output (exit_code=#{result.exit_code}): " \
                           "#{result.stdout[0, 500].inspect}"
        )
      end

      # is_error is the reliable success/failure signal (a bad call can
      # return subtype "success" with is_error true) — but a nonzero exit
      # with is_error absent is still a failure, not silently accepted.
      if result.exit_code != 0 || data["is_error"]
        return Result.new(
          error_category: :cli_failure,
          error_message:  "claude CLI call failed (subtype=#{data['subtype'].inspect}, " \
                           "errors=#{data['errors'].inspect}): #{data['result'].inspect}",
          raw: data
        )
      end

      Result.new(output: data["result"].to_s, raw: data)
    end
  end
end
