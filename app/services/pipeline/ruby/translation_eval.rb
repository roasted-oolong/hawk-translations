require "fileutils"
require "json"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslationEval
#
# Offline-only prototype harness for the translation quality pipeline idea
# in docs/ROADMAP.md — runs the 5-step pipeline (docs/DECISIONS.md's
# 2026-08-01 "5-step pipeline replaces 3-call pipeline" entry, updated by the
# 2026-08-02 hybrid beat segmentation entry) over the given chapters, writing
# all outputs to disk for a human to review. The step-calling/validation
# logic itself lives in Pipeline::Ruby::TranslateBatch::FiveStepRunner —
# shared with production translate_batch for segmentation/analysis/localization
# (production runs with run_qa: false and never calls factcheck/editor at
# all — see docs/DECISIONS.md) — this class owns only file I/O and
# ChapterResult mapping on top of it. Driven by bin/translation_eval.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslationEval
      ChapterResult = Struct.new(
        :number, :missing_source,
        :segmentation_error, :segmentation_valid_json, :segmentation_coverage_error,
        :analysis_error, :analysis_valid_json, :analysis_coverage_error,
        :localization_error, :localization_valid_json, :localization_coverage_error,
        :factcheck_error, :factcheck_valid_json, :factcheck_coverage_error, :factcheck_flagged_count,
        :editor_error, :editor_valid_json, :editor_coverage_error, :editor_flagged_count,
        keyword_init: true
      )

      def self.call(novel_dir:, chapter_numbers:, output_dir:, config: TranslationConfig.from_env)
        new(novel_dir: novel_dir, chapter_numbers: chapter_numbers, output_dir: output_dir, config: config).call
      end

      def initialize(novel_dir:, chapter_numbers:, output_dir:, config:)
        @novel_dir        = novel_dir
        @chapters_dir     = File.join(novel_dir, "chapters")
        @chapter_numbers  = chapter_numbers
        @output_dir       = output_dir
        @config           = config
      end

      def call
        runner = TranslateBatch::FiveStepRunner.build_for_novel(
          novel_dir: @novel_dir, novel_directory_name: File.basename(@novel_dir), config: @config
        )
        @chapter_numbers.map { |num| run_chapter(num, runner) }
      end

      private

      def run_chapter(num, runner)
        korean_path = File.join(@chapters_dir, "Chapter #{num} (Korean).txt")
        return ChapterResult.new(number: num, missing_source: true) unless File.exist?(korean_path)

        korean_text = File.read(korean_path, encoding: "UTF-8")
        chapter_dir = File.join(@output_dir, "chapter_#{num}")
        FileUtils.mkdir_p(chapter_dir)

        outcome = runner.run_chapter(num, korean_text)
        write_step_files(chapter_dir, outcome)

        ChapterResult.new(
          number: num, missing_source: false,
          segmentation_error: outcome.segmentation.call_error,
          segmentation_valid_json: outcome.segmentation.valid_json,
          segmentation_coverage_error: outcome.segmentation.coverage_error,
          analysis_error: outcome.analysis.call_error,
          analysis_valid_json: outcome.analysis.valid_json,
          analysis_coverage_error: outcome.analysis.coverage_error,
          localization_error: outcome.localization.call_error,
          localization_valid_json: outcome.localization.valid_json,
          localization_coverage_error: outcome.localization.coverage_error,
          factcheck_error: outcome.factcheck.call_error,
          factcheck_valid_json: outcome.factcheck.valid_json,
          factcheck_coverage_error: outcome.factcheck.coverage_error,
          factcheck_flagged_count: flagged_count(outcome.factcheck),
          editor_error: outcome.editor.call_error,
          editor_valid_json: outcome.editor.valid_json,
          editor_coverage_error: outcome.editor.coverage_error,
          editor_flagged_count: flagged_count(outcome.editor)
        )
      end

      def flagged_count(step)
        step.parsed && TranslateBatch::FiveStepRunner.count_flagged_passages(step.parsed)
      end

      def write_step_files(chapter_dir, outcome)
        if outcome.classification
          File.write(File.join(chapter_dir, "classification.json"), JSON.pretty_generate(outcome.classification), encoding: "UTF-8")
        end

        write_step_output(chapter_dir, "segmentation", outcome.segmentation)
        write_step_output(chapter_dir, "analysis", outcome.analysis)
        write_step_output(chapter_dir, "localization", outcome.localization)
        if outcome.assembled_text
          File.write(File.join(chapter_dir, "localized_chapter.txt"), outcome.assembled_text, encoding: "UTF-8")
        end
        write_step_output(chapter_dir, "factcheck", outcome.factcheck)
        write_step_output(chapter_dir, "editor", outcome.editor)
      end

      # Mirrors the original inline behavior exactly: a step whose own call
      # failed (call_error set, raw_output nil) writes nothing; a step whose
      # call succeeded but didn't parse as JSON (valid_json == false) writes
      # its raw output for inspection; a step that parsed but failed block-
      # level coverage before producing final passages (segmentation only —
      # valid_json true, parsed nil) writes nothing beyond classification.json
      # above; anything else with parsed output writes its JSON.
      def write_step_output(chapter_dir, name, step)
        return if step.call_error && step.raw_output.nil?

        if step.valid_json == false
          File.write(File.join(chapter_dir, "#{name}.raw.txt"), step.raw_output, encoding: "UTF-8")
        elsif step.parsed
          File.write(File.join(chapter_dir, "#{name}.json"), JSON.pretty_generate(step.parsed), encoding: "UTF-8")
        end
      end
    end
  end
end
