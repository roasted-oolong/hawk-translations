require "json"
require "securerandom"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::ChapterQa
#
# Public entry point PipelineDispatcher#call calls directly (bypassing
# PipelineImplementation — see its own comment) for "chapter_qa" jobs.
# Reviews a chapter's ALREADY-SAVED translation (Chapter#translated_output)
# with two independent QA passes — factcheck and editor — and returns a flat
# list of suggestions for ChapterReviewController's track-changes UI. Does
# not read or write Chapter itself; PipelineJob's update_chapters has no
# case for this job_type by design (see its own comment), so everything
# this class produces lands in TranslationJob#result_payload only.
#
# Deliberately not modeled on Pipeline::Ruby::TranslationEval's 5-step
# chain: there's no segmentation, analysis, or re-localization here, just
# two flat calls against the whole chapter's existing Korean/English text
# (see docs/DECISIONS.md's chapter_qa entry for why — this reviews what was
# already translated, it doesn't produce a new translation to review
# instead). Modeled on Pipeline::Ruby::PostTranslationReview's shape
# instead: self.call(job, config:), write_progress, project_root, same
# [stdout_json, error_message, success_bool] return contract.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class ChapterQa
      def self.call(job, config: TranslationConfig.from_env)
        new(job, config: config).call
      end

      def initialize(job, config:)
        @job          = job
        @config       = config
        @novel_dir    = File.join(project_root, job.novel.directory_name)
        @chapters_dir = File.join(@novel_dir, "chapters")
      end

      def call
        english_text = Pipeline::TranslatedChapterReader.read(@chapters_dir, @job.chapter_start)
        if english_text.nil?
          return [ "", "No translated chapter file found for chapter #{@job.chapter_start}", false ]
        end

        korean_text = read_korean_source
        if korean_text.nil?
          return [ "", "No Korean source file found for chapter #{@job.chapter_start}", false ]
        end

        reference_data     = TranslateBatch::PromptBuilder.load_reference_files(@novel_dir)
        narrator_note      = TranslateBatch::PromptBuilder.extract_narrator_note(reference_data[:novel_info])
        context            = TranslateBatch::PromptBuilder::TranslationContext.new(**reference_data, narrator_note: narrator_note)
        cultural_patterns  = read_cultural_patterns

        factcheck_suggestions, factcheck_error = run_pass(
          system_prompt: TranslateBatch::PromptBuilder.build_chapter_qa_factcheck_system_prompt(context, cultural_patterns: cultural_patterns),
          user_message:  TranslateBatch::PromptBuilder.build_chapter_qa_factcheck_user_message(korean_text: korean_text, english_text: english_text),
          checked_text:  english_text, source: "factcheck", model: @config.factcheck_model
        )
        return [ "", "factcheck: #{factcheck_error}", false ] if factcheck_error

        write_progress(50)

        editor_suggestions, editor_error = run_pass(
          system_prompt: TranslateBatch::PromptBuilder.build_chapter_qa_editor_system_prompt,
          user_message:  TranslateBatch::PromptBuilder.build_chapter_qa_editor_user_message(english_text: english_text),
          checked_text:  english_text, source: "editor"
        )
        return [ "", "editor: #{editor_error}", false ] if editor_error

        write_progress(100)

        [ JSON.generate({ suggestions: factcheck_suggestions + editor_suggestions }), "", true ]
      end

      private

      # Shared by both passes: call, parse, and normalize into the flat
      # suggestion shape the review UI expects (source/id/status added here
      # since neither prompt asks the model for them). A finding whose
      # `quote` isn't an actual substring of the text it was checked against
      # is dropped, not kept — an unanchored quote can't be located to
      # render as a tracked-change span, so keeping it would just surface a
      # suggestion the UI can never place.
      def run_pass(system_prompt:, user_message:, checked_text:, source:, model: nil)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: user_message, config: @config, model: model
        )
        return [ nil, "#{result.error_category}: #{result.error_message}" ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          return [ nil, "invalid JSON (#{e.message})" ]
        end

        suggestions = (parsed["suggestions"] || [])
          .select { |finding| checked_text.include?(finding["quote"].to_s) }
          .map do |finding|
            {
              "id"                 => SecureRandom.uuid,
              "source"             => source,
              "quote"              => finding["quote"],
              "issue"              => finding["issue"],
              "suggested_revision" => finding["suggested_revision"],
              "severity"           => finding["severity"],
              "korean_context"     => finding["korean_context"],
              "status"             => "pending"
            }
          end

        [ suggestions, nil ]
      end

      def read_korean_source
        path = File.join(@chapters_dir, "Chapter #{@job.chapter_start} (Korean).txt")
        File.exist?(path) ? File.read(path, encoding: "UTF-8") : nil
      end

      def read_cultural_patterns
        path = File.join(@novel_dir, "bible", "cultural_patterns.md")
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
