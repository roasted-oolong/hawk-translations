require "base64"
require "json"
require "marcel"

# ---------------------------------------------------------------------------
# Pipeline::ClaudeVision
#
# Ruby port of ocr_chapter.py#transcribe_image — one `claude` CLI call per
# source photo, using --input-format stream-json to send a base64 image
# content block. A separate class from Pipeline::ClaudeCode, not a shared
# parent: the two have almost nothing in common beyond "shell out to the
# claude binary" (different --input-format, an image block instead of
# plain-text stdin, no MCP config ever, its own model/budget env, and
# --output-format stream-json instead of a single json blob).
#
# Same env-allowlist discipline as Pipeline::ClaudeCode: built additively
# from {}, never a deny-list carved out of ENV.to_h, so ANTHROPIC_API_KEY
# (which would otherwise silently shadow the subscription OAuth this depends
# on) is never forwarded unless explicitly added.
# ---------------------------------------------------------------------------
module Pipeline
  class ClaudeVision
    # Matches ocr_chapter.py's own TIMEOUT_SECONDS — a single page/spread is a
    # much smaller call than a full-chapter translation, hence far shorter
    # than Pipeline::ClaudeCode's 1200s default.
    DEFAULT_TIMEOUT = 120

    SYSTEM_PROMPT = <<~PROMPT.strip
      You transcribe Korean text from an image of a novel manuscript page, exactly as written.

      Rules:
      - Preserve paragraph breaks, dialogue quotation marks, and line structure as they appear.
      - Do not translate, summarize, paraphrase, or add anything not present in the image.
      - If the image shows a two-page spread, transcribe the left page fully, then the
        right page. If a sentence is split across the page boundary, join it into one
        sentence rather than leaving it broken.
      - If a character is genuinely illegible (not just stylistically unusual), write
        the literal placeholder [?] in its place instead of guessing a plausible-looking
        substitute. Never silently invent or "correct" text.
      - Output only the transcribed text. No commentary, no preamble, no markdown fencing.
    PROMPT

    # error_category is nil on success. On failure it's one of:
    # :binary_not_found, :timeout, :killed (exit_code 137/SIGKILL — no such
    # case is named in ocr_chapter.py itself, added anyway for consistency
    # with every other subprocess primitive in this app), :cli_failure
    # (nonzero exit, no result event, or a result event with is_error true).
    Result = Struct.new(:output, :error_category, :error_message, keyword_init: true) do
      def success?
        error_category.nil?
      end
    end

    def self.call(image_path:, claude_bin:, model:, max_budget_usd:, timeout: DEFAULT_TIMEOUT, process_env: ENV)
      new(image_path: image_path, claude_bin: claude_bin, model: model, max_budget_usd: max_budget_usd,
          timeout: timeout, process_env: process_env).call
    end

    def initialize(image_path:, claude_bin:, model:, max_budget_usd:, timeout:, process_env:)
      @image_path      = image_path
      @claude_bin      = claude_bin
      @model           = model
      @max_budget_usd  = max_budget_usd
      @timeout         = timeout
      @process_env     = process_env
    end

    def call
      subprocess_result = Pipeline::Subprocess.run(
        argv, env: allowlisted_env, timeout: @timeout, name: "claude_vision", stdin: stream_input
      )
    rescue Errno::ENOENT
      Result.new(error_category: :binary_not_found,
                 error_message:  "claude CLI binary not found at #{@claude_bin}")
    else
      interpret(subprocess_result)
    end

    private

    def stream_input
      media_type = Marcel::MimeType.for(name: @image_path)
      image_b64  = Base64.strict_encode64(File.binread(@image_path))

      JSON.generate({
        type: "user",
        message: {
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: media_type, data: image_b64 } },
            { type: "text", text: "Transcribe this page." }
          ]
        }
      }) + "\n"
    end

    # Order mirrors ocr_chapter.py's own cmd list, so the two implementations
    # stay easy to diff against each other.
    def argv
      [
        @claude_bin, "-p",
        "--system-prompt", SYSTEM_PROMPT,
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
        "--model", @model,
        "--tools", "",
        "--permission-mode", "bypassPermissions",
        "--no-session-persistence",
        "--max-budget-usd", @max_budget_usd.to_s
      ]
    end

    # Built additively from {} — never a deny-list carved out of ENV.to_h.
    def allowlisted_env
      env = { "MCP_CONNECTION_NONBLOCKING" => "false" }
      env["HOME"] = @process_env["HOME"] if @process_env["HOME"]
      env
    end

    def interpret(result)
      case result.status
      when :timed_out
        return Result.new(error_category: :timeout,
                           error_message: "claude CLI call timed out after #{@timeout}s on #{@image_path}")
      when :cancelled
        return Result.new(error_category: :cancelled,
                           error_message: "claude CLI call was cancelled for #{@image_path}")
      end

      if result.exit_code == 137
        return Result.new(error_category: :killed,
                           error_message: "claude CLI process was killed (exit_code 137, possible OOM) on #{@image_path}")
      end

      if result.exit_code != 0
        return Result.new(error_category: :cli_failure,
                           error_message: "claude CLI exited #{result.exit_code} on #{@image_path}: #{result.stderr[0, 500]}")
      end

      extract_result_text(result.stdout)
    end

    # --output-format stream-json emits one JSON object per line; the final
    # "result"-type line carries the completed response and error state.
    def extract_result_text(stdout)
      result_event = nil
      stdout.each_line do |line|
        line = line.strip
        next if line.empty?

        event = JSON.parse(line)
        result_event = event if event["type"] == "result"
      end

      if result_event.nil?
        return Result.new(error_category: :cli_failure,
                           error_message: "claude CLI produced no result event for #{@image_path}: #{stdout[0, 500].inspect}")
      end

      if result_event["is_error"]
        return Result.new(
          error_category: :cli_failure,
          error_message:  "claude CLI reported error for #{@image_path} " \
                           "(subtype=#{result_event['subtype'].inspect}): #{result_event['result'].inspect}"
        )
      end

      Result.new(output: result_event["result"].to_s.strip)
    rescue JSON::ParserError => e
      Result.new(error_category: :cli_failure,
                 error_message: "claude CLI produced unparseable stream-json output for #{@image_path}: #{e.message}")
    end
  end
end
