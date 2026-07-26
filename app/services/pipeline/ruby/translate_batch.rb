require "fileutils"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslateBatch
#
# Ruby port of translate_batch.py's orchestration, per R4 in
# docs/RAILS_REFACTOR_PLAN.md — the first Ruby job-type implementation to
# build a real --mcp-config pointing at bin/mcp_skill_bridge (R3) and drive
# Pipeline::ClaudeCode (R1) with it.
#
# Orchestrates only: load references -> build context -> build prompt ->
# invoke Pipeline::ClaudeCode -> write file -> report progress. Translation,
# search, bible formatting, MCP, and subprocess mechanics all stay owned by
# R1-R3 — nothing here reimplements them.
#
# CLI-only surface from translate_batch.py (arg parsing, interactive chapter
# prompting/confirmation, novel-name disambiguation) has no port here:
# TranslationJob already carries chapter_start/chapter_end from the web UI,
# so chapter selection is solved before this class runs.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslateBatch
      # Caused by the one chapter's own request (a slow response, a transient
      # CLI hiccup, a killed job, or a one-off unparseable response) —
      # doesn't predict whether the next chapter will succeed. The batch
      # continues past these, matching translate_batch.py's per-request
      # try/except/continue behavior.
      #
      # :unparseable_output is bucketed here, not in FATAL_CATEGORIES: the
      # design doc's recoverable/fatal split (docs/RAILS_REFACTOR_PLAN.md,
      # R4) named the other five categories explicitly but didn't rule on
      # this one. A single response failing to parse as JSON is a property
      # of that one call, not of the batch as a whole, so it gets the same
      # "continue" treatment as :cli_failure rather than halting the job.
      RECOVERABLE_CATEGORIES = %i[timeout cli_failure cancelled unparseable_output].freeze

      # True for the whole job, not the one chapter — every remaining
      # chapter is guaranteed to fail identically, so continuing would only
      # burn the rest of the 4-hour job timeout on outcomes already known.
      # :killed defaults to fatal here (no dmesg/container-events check
      # exists yet to confirm OOM per R0.3's still-unmeasured baseline) —
      # the conservative reading of "OOM-traceable :killed is fatal."
      FATAL_CATEGORIES = %i[binary_not_found killed].freeze

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
        chapter_nums = (@job.chapter_start..@job.chapter_end).to_a
        requests, missing_source = partition_by_source_availability(chapter_nums)

        if requests.empty?
          return [ "Nothing to submit — no Korean source files found for the requested chapters.", "", true ]
        end

        reference_data = PromptBuilder.load_reference_files(@novel_dir)
        narrator_note  = PromptBuilder.extract_narrator_note(reference_data[:novel_info])
        context        = PromptBuilder::TranslationContext.new(**reference_data, narrator_note: narrator_note)
        system_prompt  = PromptBuilder.build_system_prompt(context)
        mcp_config     = BridgeConfig.mcp_config(novel_directory_name: @job.novel.directory_name)

        write_progress(1)
        written, failures, aborted, stop_reason = run_batch(requests, system_prompt, mcp_config)

        [ build_stdout(written, missing_source, aborted, stop_reason),
          build_stderr(failures, aborted, stop_reason),
          failures.empty? ]
      end

      private

      # Checked between chapters, not during one — this can't interrupt a
      # chapter's own in-flight `claude` call (Pipeline::ClaudeCode has no
      # cancel_token wired through Pipeline::Subprocess for that), only stop
      # the batch from starting further chapters once a cancellation lands.
      # Whatever this chapter already wrote to disk before the check is kept
      # by PipelineJob's own cancelled-phase handling, not discarded.
      def run_batch(requests, system_prompt, mcp_config)
        written  = []
        failures = []
        total    = requests.size

        requests.each_with_index do |(num, korean_path), index|
          korean_text = File.read(korean_path, encoding: "UTF-8")

          result = Pipeline::ClaudeCode.call(
            system_prompt: system_prompt,
            user_message:  korean_text,
            config:        @config,
            mcp_config:    mcp_config
          )

          if result.success?
            write_chapter_output(num, result.output)
            written << num
            write_progress((written.size.to_f / total * 100).to_i)
          else
            failures << { number: num, error_category: result.error_category, error_message: result.error_message }
            if FATAL_CATEGORIES.include?(result.error_category)
              remaining = requests[(index + 1)..].map(&:first)
              return [ written, failures, remaining, :fatal_error ]
            end
          end

          if @job.reload.cancelled?
            remaining = requests[(index + 1)..].map(&:first)
            return [ written, failures, remaining, :cancelled ]
          end
        end

        [ written, failures, [], nil ]
      end

      # Returns [requests, missing_source] where requests is
      # [[chapter_num, korean_path], ...] for chapters with a source file on
      # disk, in chapter order — mirrors translate_batch.py's own skip of
      # chapters with no Korean source (a routine, non-error condition, not
      # one of Pipeline::ClaudeCode's error categories).
      def partition_by_source_availability(chapter_nums)
        requests = []
        missing  = []
        chapter_nums.each do |num|
          path = find_korean_source(num)
          path ? requests << [ num, path ] : missing << num
        end
        [ requests, missing ]
      end

      # Matches KoreanSourceDiskWriter's on-disk convention — the only
      # writer of Korean source files, so it's the only convention that
      # matters here.
      def find_korean_source(num)
        path = File.join(@chapters_dir, "Chapter #{num} (Korean).txt")
        File.exist?(path) ? path : nil
      end

      # .tmp-then-rename: atomic on the same filesystem, so a crash mid-write
      # (including the fatal :killed/OOM case) never leaves a truncated file
      # observable at the final path — translate_batch.py's own plain
      # write_text has no such guarantee, a deliberate improvement named in
      # the R4 design (Finding 1), not a flagged-only gap.
      def write_chapter_output(num, text)
        final_path = File.join(@chapters_dir, "Chapter #{num}.txt")
        tmp_path   = "#{final_path}.tmp"
        File.write(tmp_path, text, encoding: "UTF-8")
        File.rename(tmp_path, final_path)
      end

      def build_stdout(written, missing_source, aborted, stop_reason)
        lines = [ "#{written.size} chapter(s) translated." ]
        lines << "Skipped (missing source files): #{missing_source.sort.inspect}" if missing_source.any?
        lines << "Not attempted (#{stop_description(stop_reason)}): #{aborted.sort.inspect}" if aborted.any?
        lines.join("\n")
      end

      def build_stderr(failures, aborted, stop_reason)
        return "" if failures.empty? && aborted.empty?

        lines = failures.map { |f| "Chapter #{f[:number]}: #{f[:error_category]} — #{f[:error_message]}" }
        lines << "Batch stopped (#{stop_description(stop_reason)}); chapters #{aborted.sort.inspect} were not attempted." if aborted.any?
        lines.join("\n")
      end

      def stop_description(stop_reason)
        stop_reason == :cancelled ? "job was cancelled" : "batch stopped after a fatal error"
      end

      def write_progress(pct)
        File.write("/tmp/hawk_job_#{@job.id}.progress", pct.clamp(0, 100).to_s)
      end

      def project_root
        ENV.fetch("HAWK_PROJECT_ROOT") do
          raise "HAWK_PROJECT_ROOT environment variable is not set."
        end
      end
    end
  end
end
