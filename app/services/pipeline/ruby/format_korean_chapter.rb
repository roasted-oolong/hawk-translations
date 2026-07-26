# ---------------------------------------------------------------------------
# Pipeline::Ruby::FormatKoreanChapter
#
# Ruby port of clean_chapter.py's main() — public entry point
# FormatKoreanChapterJob#run_cleaner calls for the "formatter" job type.
# Read -> build prompt -> call the configured backend -> parse -> return.
#
# clean_chapter.py itself now dispatches through get_backend(FORMAT_BACKEND)
# (2026-07-25 migration, same seam as translate_batch/preread/review),
# defaulting to "claude_code" — NOT the Ollama-only path R6.5's original
# design assumed. This orchestrator mirrors that dispatch so flipping
# PIPELINE_IMPL_FORMATTER=ruby reproduces Python's actual current default
# rather than silently downgrading every formatting call to local-Ollama
# quality: Pipeline::ClaudeCode for "claude_code" (the default),
# Pipeline::LocalLlmChat for "local". Both primitives return a Result with
# the same (output, error_category, error_message, success?) shape, so the
# call-result handling below is backend-agnostic.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class FormatKoreanChapter
      # Matches FormatKoreanChapterJob's own CLEANER_TIMEOUT_SECONDS — a full
      # chapter's cleanup on a CPU-only local model can take 20-40+ minutes;
      # applied here regardless of which backend is selected, since neither
      # backend primitive owns this policy itself (see each primitive's own
      # comment).
      TIMEOUT_SECONDS = 1800

      CHAPTER_KEY = 1

      Result = Struct.new(:output, :error_message, keyword_init: true) do
        def success?
          error_message.nil?
        end
      end

      def self.call(text, config: TranslationConfig.from_env,
                    model: ENV.fetch("HAIKU_MODEL", "qwen2.5:7b"),
                    max_tokens: ENV.fetch("FORMAT_MAX_TOKENS", "64000").to_i)
        new(text, config: config, model: model, max_tokens: max_tokens).call
      end

      def initialize(text, config:, model:, max_tokens:)
        @text       = text
        @config     = config
        @model      = model
        @max_tokens = max_tokens
      end

      def call
        return Result.new(error_message: "empty input") if @text.nil? || @text.strip.empty?

        system_prompt = FormatterPromptBuilder.build_system_prompt
        user_message  = FormatterPromptBuilder.build_user_message({ CHAPTER_KEY => @text })

        call_result = call_backend(system_prompt, user_message)
        unless call_result.success?
          return Result.new(error_message: "#{call_result.error_category}: #{call_result.error_message}")
        end

        parsed = FormatterResponseParser.parse(call_result.output, [ CHAPTER_KEY ])
        unless parsed.chapters.key?(CHAPTER_KEY)
          return Result.new(error_message: "failed to parse LLM response: #{call_result.output.to_s[0, 500]}")
        end

        Result.new(output: parsed.chapters[CHAPTER_KEY])
      end

      private

      def call_backend(system_prompt, user_message)
        if @config.format_backend == "local"
          Pipeline::LocalLlmChat.call(
            system_prompt: system_prompt, user_message: user_message,
            base_url: @config.llm_base_url, api_key: @config.llm_api_key,
            model: @model, max_tokens: @max_tokens, timeout: TIMEOUT_SECONDS
          )
        else
          Pipeline::ClaudeCode.call(
            system_prompt: system_prompt, user_message: user_message,
            config: @config, mcp_config: nil, timeout: TIMEOUT_SECONDS
          )
        end
      end
    end
  end
end
