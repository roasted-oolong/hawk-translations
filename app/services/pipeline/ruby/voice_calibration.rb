# ---------------------------------------------------------------------------
# Pipeline::Ruby::VoiceCalibration
#
# Ruby port of calibrate-voice.py — public entry point PipelineDispatcher#dispatch_ruby
# calls for "voice_calibration" jobs. Read -> build prompt -> call
# Pipeline::ClaudeCode -> parse -> emit cards. Performs no file writes of any
# kind (calibrate-voice.py never touches disk either) — every actual write
# already lives in the shipped VoiceCalibrationReviewController/
# VoiceCalibrationDocWriter, gated behind the human review step those
# already provide. See docs/RAILS_REFACTOR_PLAN.md's R5 section.
#
# Moves onto Pipeline::ClaudeCode (the claude_code backend) rather than a
# ported src/agent.py "local" call — a deliberate, user-confirmed departure
# from calibrate-voice.py's CALIBRATION_BACKEND selection, extending the
# same quality-ceiling reasoning documented in docs/DECISIONS.md's
# 2026-07-21 entry. No --mcp-config/bridge: verified neither Python prompt
# instructs tool use.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class VoiceCalibration
      def self.call(job, config: TranslationConfig.from_env)
        new(job, config: config).call
      end

      def initialize(job, config:)
        @job            = job
        @config         = config
        @novel_dir      = File.join(project_root, job.novel.directory_name)
        @chapters_dir   = File.join(@novel_dir, "chapters")
      end

      def call
        translated_chapter = Pipeline::TranslatedChapterReader.read(@chapters_dir, @job.chapter_start)
        if translated_chapter.nil?
          return [ "", "No translated chapter file found for chapter #{@job.chapter_start}", false ]
        end

        write_progress(50)

        context = PromptBuilder::ReviewContext.new(
          voice_calibration:  read_voice_calibration,
          translated_chapter: translated_chapter,
          chapter_num:        @job.chapter_start
        )

        call_result = Pipeline::ClaudeCode.call(
          system_prompt: PromptBuilder.build_system_prompt,
          user_message:  PromptBuilder.build_user_message(context),
          config:        @config,
          mcp_config:    nil
        )
        unless call_result.success?
          return [ "", "#{call_result.error_category}: #{call_result.error_message}", false ]
        end

        parsed = ResponseParser.parse(call_result.output)
        unless parsed.success?
          return [ "", "#{parsed.failure_reason}: #{parsed.error_message}", false ]
        end

        write_progress(100)
        [ JSON.generate({ cards: parsed.cards.map(&:to_card_hash) }), "", true ]
      end

      private

      def read_voice_calibration
        path = File.join(@novel_dir, "bible", "voice_calibration.md")
        File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
      end

      def write_progress(pct)
        File.write("/tmp/hawk_job_#{@job.id}.progress", pct.to_s)
      end

      def project_root
        ENV.fetch("HAWK_PROJECT_ROOT") do
          raise "HAWK_PROJECT_ROOT environment variable is not set."
        end
      end
    end
  end
end
