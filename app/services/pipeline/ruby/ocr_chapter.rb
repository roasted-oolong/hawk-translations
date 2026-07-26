# ---------------------------------------------------------------------------
# Pipeline::Ruby::OcrChapter
#
# Ruby port of ocr_chapter.py's main()/transcribe_image loop — public entry
# point OcrChapterJob#run_ocr calls for the "ocr" job type. Calls
# Pipeline::ClaudeVision once per image path, in argv order (never
# re-sorted — page order is the caller's sole authority, per
# ocr_chapter.py's own docstring), and joins successful transcriptions with
# "\n\n".
#
# Deliberate divergence from translate_batch's continue-on-recoverable-
# failure policy: this returns a single failure Result on the first
# per-image error rather than a partial-success list, matching
# ocr_chapter.py's "exits immediately without writing partial output"
# behavior exactly — a chapter missing its middle page is worse than a
# chapter that fails outright and can be re-run.
#
# No backend branching (unlike the formatter): ocr_chapter.py has no
# *_BACKEND toggle of its own, it always shells out to the claude CLI.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class OcrChapter
      # Matches ocr_chapter.py's own TIMEOUT_SECONDS.
      TIMEOUT_SECONDS = 120

      Result = Struct.new(:output, :error_message, keyword_init: true) do
        def success?
          error_message.nil?
        end
      end

      def self.call(image_paths, config: TranslationConfig.from_env,
                    model: ENV.fetch("OCR_MODEL", "claude-sonnet-5"),
                    max_budget_usd: ENV.fetch("OCR_MAX_BUDGET_USD", "0.50"))
        new(image_paths, config: config, model: model, max_budget_usd: max_budget_usd).call
      end

      def initialize(image_paths, config:, model:, max_budget_usd:)
        @image_paths     = image_paths
        @config          = config
        @model           = model
        @max_budget_usd  = max_budget_usd
      end

      def call
        return Result.new(error_message: "no image paths given") if @image_paths.blank?

        transcriptions = []
        @image_paths.each do |path|
          call_result = Pipeline::ClaudeVision.call(
            image_path: path, claude_bin: @config.claude_bin,
            model: @model, max_budget_usd: @max_budget_usd, timeout: TIMEOUT_SECONDS
          )
          unless call_result.success?
            return Result.new(
              error_message: "failed to transcribe #{path}: #{call_result.error_category}: #{call_result.error_message}"
            )
          end

          transcriptions << call_result.output
        end

        Result.new(output: transcriptions.join("\n\n"))
      end
    end
  end
end
