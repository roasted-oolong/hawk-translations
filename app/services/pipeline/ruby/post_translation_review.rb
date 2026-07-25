require "date"
require "digest"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::PostTranslationReview
#
# Ruby port of run_review.py — public entry point PipelineDispatcher#dispatch_ruby
# calls for "post_translation_review" jobs. Read -> build prompt -> call
# Pipeline::ClaudeCode -> parse -> emit review cards. Narrower than a literal
# port of run_review.py's end-to-end behavior: this class never writes to
# disk. run_review.py's auto-apply behavior is deliberately not ported — all
# three mutation types now require human review through
# PostTranslationReviewController + Pipeline::BibleReviewWriter, matching
# voice_calibration's existing review-then-commit pattern. See
# docs/RAILS_REFACTOR_PLAN.md's R5 section for the full reasoning.
#
# Moves onto Pipeline::ClaudeCode (the claude_code backend) rather than a
# ported src/agent.py "local" call — a deliberate, user-confirmed departure
# from run_review.py's current production behavior (which stays on the
# local Ollama backend per docs/DECISIONS.md's 2026-07-21 entry). No
# --mcp-config/bridge: verified the bible_review system prompt never
# instructs tool use.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class PostTranslationReview
      BIBLE_FILES = {
        "characters"       => "bible/characters.md",
        "cultural_phrases" => "bible/cultural_phrases.md",
        "locations"        => "bible/locations.md",
        "story"            => "bible/story.md",
        "terminology"      => "bible/terminology.md"
      }.freeze

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
        translated_chapter = Pipeline::TranslatedChapterReader.read(@chapters_dir, @job.chapter_start)
        if translated_chapter.nil?
          return [ "", "No translated chapter file found for chapter #{@job.chapter_start}", false ]
        end

        # Read once, immediately after which the SHA-256 fingerprint below is
        # captured — the same read this call's prompt uses, not a second
        # fresh read, since the fingerprint's job is to detect *later*
        # drift relative to this exact generation-time snapshot.
        bible          = read_bible_files
        bible_revision = bible.transform_values { |content| Digest::SHA256.hexdigest(content) }
        today          = Date.current.iso8601

        write_progress(50)

        context = PromptBuilder::ReviewContext.new(
          novel_info:         read_novel_info,
          characters:         bible["characters"],
          cultural_phrases:   bible["cultural_phrases"],
          locations:          bible["locations"],
          story:              bible["story"],
          terminology:        bible["terminology"],
          translated_chapter: translated_chapter,
          chapter_num:        @job.chapter_start,
          today:              today
        )

        call_result = Pipeline::ClaudeCode.call(
          system_prompt: PromptBuilder.build_system_prompt(today, @job.chapter_start),
          user_message:  PromptBuilder.build_user_message(context),
          config:        @config,
          mcp_config:    nil
        )
        unless call_result.success?
          return [ "", "#{call_result.error_category}: #{call_result.error_message}", false ]
        end

        # Response-level size/count/field-length limits are enforced inside
        # ResponseParser.parse itself, immediately after the API call
        # returns and before any card is constructed — see its own comment
        # for why that's a different validation layer than BibleReviewWriter's.
        parsed = ResponseParser.parse(call_result.output)
        unless parsed.success?
          return [ "", "#{parsed.failure_reason}: #{parsed.error_message}", false ]
        end

        write_progress(100)

        cards = (parsed.new_entries + parsed.proposed_edits + parsed.story_updates).map(&:to_card_hash)
        [ JSON.generate({ cards: cards, bible_revision: bible_revision }), "", true ]
      end

      private

      def read_bible_files
        BIBLE_FILES.transform_values { |relative_path| read_file(File.join(@novel_dir, relative_path)) }
      end

      def read_novel_info
        read_file(File.join(@novel_dir, "novel_info.md"))
      end

      def read_file(path)
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
