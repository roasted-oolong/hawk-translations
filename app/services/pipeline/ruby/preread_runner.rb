require "date"
require "set"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::PrereadRunner
#
# Ruby port of src/preread/runner.py — the shared batch-loop orchestrator
# for both the preread and bible_build job types. Not registered in
# PipelineDispatcher directly; Pipeline::Ruby::Preread and
# Pipeline::Ruby::BibleBuild are thin public callers that each supply their
# own chapter-discovery predicate and batch size (see docs/RAILS_REFACTOR_PLAN.md
# R6 — "one runner, two callers", mirroring run_preread.py/run_bible_build.py
# both calling the same run_preread()).
#
# Per batch: re-read the 5 bible files + novel_info.md fresh (so the
# previous batch's writes are visible — cross-batch dedup depends on this),
# build the prompt, call Pipeline::ClaudeCode, parse the response, hand the
# parsed sections to Pipeline::PrereadBibleWriter, advance the job's
# progress file. On any batch's call failure or a response missing its
# section markers entirely, the loop stops — batches already written keep
# their writes, since each batch's write already landed atomically before
# the next batch started (no partial-batch corruption to roll back, only
# "fewer batches completed than requested").
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class PrereadRunner
      # Relative paths of the 5 bible files preread/bible_build read and may
      # update — mirrors src/preread/bible_reader.py's PREREAD_BIBLE_FILES
      # (config.NOVEL_FILES filtered to location == "bible", minus
      # voice_calibration, which preread has no use for).
      BIBLE_FILES = %w[
        bible/characters.md
        bible/cultural_phrases.md
        bible/locations.md
        bible/story.md
        bible/terminology.md
      ].freeze

      def self.call(job, discovery:, batch_size:, config: TranslationConfig.from_env)
        new(job, discovery: discovery, batch_size: batch_size, config: config).call
      end

      def initialize(job, discovery:, batch_size:, config:)
        @job          = job
        @discovery    = discovery
        @batch_size   = batch_size
        @config       = config
        @novel_dir    = File.join(project_root, job.novel.directory_name)
        @chapters_dir = File.join(@novel_dir, "chapters")
        @writer       = Pipeline::PrereadBibleWriter.new(@novel_dir)
        @log          = []
      end

      def call
        available = @discovery.call(@chapters_dir)
        filtered  = ChapterDiscovery.filter_to_available((@job.chapter_start..@job.chapter_end).to_a, available)
        note_skipped(filtered.skipped)

        chapter_nums = filtered.selected
        return [ finish_log("No chapters to process."), "", true ] if chapter_nums.empty?

        today         = Date.current.iso8601
        system_prompt = PromptBuilder.build_system_prompt(today)
        batches       = chapter_nums.each_slice(@batch_size).to_a

        write_progress(1)
        run_batches(batches, system_prompt, today)
      rescue => e
        [ @log.join("\n"), "Unexpected error: #{e.class}: #{e.message}", false ]
      end

      private

      def run_batches(batches, system_prompt, today)
        total = batches.length
        batches.each_with_index do |batch_nums, index|
          outcome = run_batch(batch_nums, system_prompt, today)
          return [ @log.join("\n"), outcome[:error], false ] unless outcome[:success]

          write_progress(((index + 1).to_f / total * 100).to_i)
        end
        [ @log.join("\n"), "", true ]
      end

      def run_batch(batch_nums, system_prompt, today)
        bible      = read_bible_files
        novel_info = read_novel_info
        chapters_content = batch_nums.index_with { |n| read_chapter_file(n) }

        context = PromptBuilder::PrereadContext.new(
          novel_info:        novel_info,
          characters:        bible["bible/characters.md"],
          cultural_phrases:  bible["bible/cultural_phrases.md"],
          locations:         bible["bible/locations.md"],
          story:             bible["bible/story.md"],
          terminology:       bible["bible/terminology.md"],
          chapters:          chapters_content,
          today:             today
        )
        user_message = PromptBuilder.build_user_message(context)

        call_result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: user_message,
          config: @config, mcp_config: nil
        )
        unless call_result.success?
          return { success: false, error: "claude call failed for chapters #{batch_nums.inspect}: #{call_result.error_message}" }
        end

        parsed = ResponseParser.parse(call_result.output)
        if parsed.missing_markers
          return { success: false, error: "response missing section markers for chapters #{batch_nums.inspect}" }
        end

        status = @writer.write_batch(parsed.sections)
        @log << "Chapters #{batch_nums.join(', ')} — #{summarize_status(status)}"
        { success: true }
      end

      def summarize_status(status)
        written = status.select { |_, v| v == :written }.keys
        written.any? ? "wrote: #{written.join(', ')}" : "(nothing to add)"
      end

      def note_skipped(skipped)
        return if skipped.empty?
        @log << "Skipping chapters not found or already translated: #{skipped.sort.inspect}"
      end

      def finish_log(message)
        @log << message
        @log.join("\n")
      end

      def read_bible_files
        BIBLE_FILES.index_with { |rel| read_file(File.join(@novel_dir, rel)) }
      end

      def read_novel_info
        read_file(File.join(@novel_dir, "novel_info.md"))
      end

      def read_chapter_file(num)
        path = File.join(@chapters_dir, "Chapter #{num} (Korean).txt")
        File.exist?(path) ? File.read(path, encoding: "UTF-8") : "[ERROR: Chapter #{num} (Korean).txt not found at #{path}]"
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
