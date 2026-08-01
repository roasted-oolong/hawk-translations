require "fileutils"
require "json"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslationEval
#
# Offline-only prototype harness for the translation quality pipeline idea
# in docs/ROADMAP.md — runs the 5-step pipeline (docs/DECISIONS.md's
# 2026-08-01 "5-step pipeline replaces 3-call pipeline" entry, updated by the
# 2026-08-02 hybrid beat segmentation entry) over the given chapters, writing
# all outputs to disk for a human to review. Not wired into
# translate_batch.rb, PipelineJob, or any TranslationJob: the point is to
# judge quality/cost/JSON-reliability before committing to any change in
# production behavior. Driven by bin/translation_eval.
#
# The 5-step pipeline chains strictly: segmentation -> analysis ->
# localization -> {factcheck, editor}. Each step only runs when the step(s)
# it depends on produced valid, fully-covered output — there's nothing
# trustworthy to chain into otherwise. factcheck and editor both depend only
# on localization, not on each other; they're independent QA passes run
# one after the other here for simplicity, not a further chain.
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
        reference_data        = TranslateBatch::PromptBuilder.load_reference_files(@novel_dir)
        narrator_note         = TranslateBatch::PromptBuilder.extract_narrator_note(reference_data[:novel_info])
        context                = TranslateBatch::PromptBuilder::TranslationContext.new(**reference_data, narrator_note: narrator_note)
        segmentation_prompt    = TranslateBatch::PromptBuilder.build_beat_classification_system_prompt(context)
        analysis_prompt        = TranslateBatch::PromptBuilder.build_analysis_system_prompt(context, cultural_patterns: read_cultural_patterns)
        localization_prompt    = TranslateBatch::PromptBuilder.build_localization_system_prompt(context, cultural_patterns: read_cultural_patterns)
        factcheck_prompt       = TranslateBatch::PromptBuilder.build_factcheck_system_prompt(context, cultural_patterns: read_cultural_patterns)
        editor_prompt          = TranslateBatch::PromptBuilder.build_editor_system_prompt
        mcp_config              = TranslateBatch::BridgeConfig.mcp_config(novel_directory_name: File.basename(@novel_dir))

        @chapter_numbers.map do |num|
          run_chapter(
            num, segmentation_prompt, analysis_prompt, localization_prompt, factcheck_prompt, editor_prompt,
            mcp_config
          )
        end
      end

      private

      # Deliberately not part of TranslateBatch::PromptBuilder::NOVEL_FILES —
      # this is eval-only reference material and must not flow into the
      # production single-pass prompt via the context both prompt builders
      # share.
      def read_cultural_patterns
        path = File.join(@novel_dir, "bible", "cultural_patterns.md")
        File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
      end

      def run_chapter(num, segmentation_prompt, analysis_prompt, localization_prompt, factcheck_prompt, editor_prompt,
                       mcp_config)
        korean_path = File.join(@chapters_dir, "Chapter #{num} (Korean).txt")
        return ChapterResult.new(number: num, missing_source: true) unless File.exist?(korean_path)

        korean_text = File.read(korean_path, encoding: "UTF-8")
        chapter_dir = File.join(@output_dir, "chapter_#{num}")
        FileUtils.mkdir_p(chapter_dir)

        segmentation_error, segmentation_valid_json, segmentation_coverage_error, segmentation_parsed =
          run_segmentation(chapter_dir, segmentation_prompt, korean_text, mcp_config)

        analysis_error, analysis_valid_json, analysis_coverage_error, analysis_parsed =
          if segmentation_error.nil? && segmentation_valid_json && segmentation_coverage_error.nil?
            run_analysis(chapter_dir, analysis_prompt, segmentation_parsed, mcp_config)
          else
            [ "skipped: segmentation did not produce valid, fully-covered passages", nil, nil, nil ]
          end

        localization_error, localization_valid_json, localization_coverage_error, localization_parsed =
          if analysis_error.nil? && analysis_valid_json && analysis_coverage_error.nil?
            run_localization(chapter_dir, localization_prompt, segmentation_parsed, analysis_parsed, mcp_config)
          else
            [ "skipped: analysis did not produce valid, fully-covered output", nil, nil, nil ]
          end

        factcheck_error, factcheck_valid_json, factcheck_coverage_error, factcheck_flagged_count =
          if localization_error.nil? && localization_valid_json && localization_coverage_error.nil?
            run_factcheck(chapter_dir, factcheck_prompt, segmentation_parsed, analysis_parsed, localization_parsed, mcp_config)
          else
            [ "skipped: localization did not produce valid, fully-covered translation", nil, nil, nil ]
          end

        editor_error, editor_valid_json, editor_coverage_error, editor_flagged_count =
          if localization_error.nil? && localization_valid_json && localization_coverage_error.nil?
            run_editor(chapter_dir, editor_prompt, localization_parsed, mcp_config)
          else
            [ "skipped: localization did not produce valid, fully-covered translation", nil, nil, nil ]
          end

        ChapterResult.new(
          number: num, missing_source: false,
          segmentation_error: segmentation_error,
          segmentation_valid_json: segmentation_valid_json,
          segmentation_coverage_error: segmentation_coverage_error,
          analysis_error: analysis_error,
          analysis_valid_json: analysis_valid_json,
          analysis_coverage_error: analysis_coverage_error,
          localization_error: localization_error,
          localization_valid_json: localization_valid_json,
          localization_coverage_error: localization_coverage_error,
          factcheck_error: factcheck_error,
          factcheck_valid_json: factcheck_valid_json,
          factcheck_coverage_error: factcheck_coverage_error,
          factcheck_flagged_count: factcheck_flagged_count,
          editor_error: editor_error,
          editor_valid_json: editor_valid_json,
          editor_coverage_error: editor_coverage_error,
          editor_flagged_count: editor_flagged_count
        )
      end

      # Step 1. Hybrid segmentation (see BeatSegmenter and
      # PromptBuilder.build_beat_classification_system_prompt): candidate_blocks
      # deterministically pre-chunks the chapter (no LLM call), one LLM call
      # classifies each block's relationship to the block before it, then
      # merge_beats deterministically assembles the final passages (no LLM
      # call). Returns [call_error, valid_json, coverage_error, parsed] — same
      # contract as before, so callers/ChapterResult need no changes. Coverage
      # here checks that every candidate block got exactly one classification,
      # in order; once merged, the same anchor_quote-reconstruction check as
      # before still applies to the final passages.
      def run_segmentation(chapter_dir, system_prompt, korean_text, mcp_config)
        candidate_blocks = TranslateBatch::BeatSegmenter.candidate_blocks(korean_text)
        classifiable_ids = candidate_blocks.reject(&:scene_break).map(&:block_id)

        user_message = TranslateBatch::PromptBuilder.build_beat_classification_user_message(candidate_blocks: candidate_blocks)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: user_message, config: @config, mcp_config: mcp_config
        )
        return [ "#{result.error_category}: #{result.error_message}", nil, nil, nil ] unless result.success?

        begin
          classification = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "segmentation.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false, nil, nil ]
        end

        File.write(File.join(chapter_dir, "classification.json"), JSON.pretty_generate(classification), encoding: "UTF-8")

        coverage_error = validate_ordered_coverage(classifiable_ids, classification["blocks"], "blocks", id_key: "block_id")
        return [ nil, true, coverage_error, nil ] if coverage_error

        parsed = { "passages" => TranslateBatch::BeatSegmenter.merge_beats(candidate_blocks, classification["blocks"]) }
        File.write(File.join(chapter_dir, "segmentation.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")
        [ nil, true, validate_segmentation(korean_text, parsed), parsed ]
      end

      # Step 2. Consumes Step 1's segmentation. Returns [call_error, valid_json,
      # coverage_error, parsed] — ordered coverage, since Step 3 needs the same
      # passage_id sequence to chain from.
      def run_analysis(chapter_dir, system_prompt, segmentation_parsed, mcp_config)
        user_message = TranslateBatch::PromptBuilder.build_analysis_user_message(segmentation_result: segmentation_parsed)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: user_message, config: @config, mcp_config: mcp_config
        )
        return [ "#{result.error_category}: #{result.error_message}", nil, nil, nil ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "analysis.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false, nil, nil ]
        end

        File.write(File.join(chapter_dir, "analysis.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")

        expected_ids = (segmentation_parsed["passages"] || []).map { |passage| passage["passage_id"] }
        coverage_error = validate_ordered_coverage(expected_ids, parsed["passages"], "passages")
        [ nil, true, coverage_error, parsed ]
      end

      # Step 3. Consumes Step 1's segmentation (for anchor_quote) and Step 2's
      # analysis, reassembles the result into a full chapter for direct review.
      # Returns [call_error, valid_json, coverage_error, parsed] — ordered
      # coverage, since reassembly is a straight concatenation and order matters
      # as much as coverage.
      def run_localization(chapter_dir, system_prompt, segmentation_parsed, analysis_parsed, mcp_config)
        user_message = TranslateBatch::PromptBuilder.build_localization_user_message(
          segmentation_result: segmentation_parsed, analysis_result: analysis_parsed
        )
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: user_message, config: @config, mcp_config: mcp_config
        )
        return [ "#{result.error_category}: #{result.error_message}", nil, nil, nil ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "localization.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false, nil, nil ]
        end

        File.write(File.join(chapter_dir, "localization.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")

        expected_ids = (analysis_parsed["passages"] || []).map { |passage| passage["passage_id"] }
        coverage_error = validate_ordered_coverage(expected_ids, parsed["localized_passages"], "localized_passages")
        if coverage_error.nil?
          reassembled = parsed["localized_passages"].map { |passage| passage["localized_translation"].to_s }.join
          File.write(File.join(chapter_dir, "localized_chapter.txt"), reassembled, encoding: "UTF-8")
        end

        [ nil, true, coverage_error, parsed ]
      end

      # Step 4. Independently checks names/facts/cultural cues survived into
      # Step 3's translation — not prose quality, that's Step 5. Only runs when
      # Step 3 produced valid JSON with full passage_id coverage. Returns
      # [call_error, valid_json, coverage_error, flagged_count]. Runs on
      # @config.factcheck_model rather than translation_model — this is a
      # verification task (do these names/facts survive), not creative
      # generation, so a cheaper model is expected to hold up.
      def run_factcheck(chapter_dir, system_prompt, segmentation_parsed, analysis_parsed, localization_parsed, mcp_config)
        user_message = TranslateBatch::PromptBuilder.build_factcheck_user_message(
          segmentation_result: segmentation_parsed, analysis_result: analysis_parsed, localization_result: localization_parsed
        )
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: user_message, config: @config,
          mcp_config: mcp_config, model: @config.factcheck_model
        )
        return [ "#{result.error_category}: #{result.error_message}", nil, nil, nil ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "factcheck.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false, nil, nil ]
        end

        File.write(File.join(chapter_dir, "factcheck.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")

        expected_ids = (localization_parsed["localized_passages"] || []).map { |passage| passage["passage_id"] }
        coverage_error = validate_set_coverage(expected_ids, parsed["reviewed_passages"], "reviewed_passages")
        [ nil, true, coverage_error, count_flagged_passages(parsed) ]
      end

      # Step 5. Reviews ONLY Step 3's English text — no Korean, no analysis (see
      # build_editor_user_message/build_editor_system_prompt). Only runs when
      # Step 3 produced valid JSON with full passage_id coverage. Returns
      # [call_error, valid_json, coverage_error, flagged_count].
      def run_editor(chapter_dir, system_prompt, localization_parsed, mcp_config)
        user_message = TranslateBatch::PromptBuilder.build_editor_user_message(localization_result: localization_parsed)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: user_message, config: @config, mcp_config: mcp_config
        )
        return [ "#{result.error_category}: #{result.error_message}", nil, nil, nil ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "editor.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false, nil, nil ]
        end

        File.write(File.join(chapter_dir, "editor.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")

        expected_ids = (localization_parsed["localized_passages"] || []).map { |passage| passage["passage_id"] }
        coverage_error = validate_set_coverage(expected_ids, parsed["reviewed_passages"], "reviewed_passages")
        [ nil, true, coverage_error, count_flagged_passages(parsed) ]
      end

      # Reassembly downstream (Step 3) is a straight concatenation, so order
      # matters as much as coverage — expected_ids and actual_ids must match
      # exactly, not just as sets. id_key defaults to "passage_id" but Step 1's
      # classification coverage check keys on "block_id" instead.
      def validate_ordered_coverage(expected_ids, actual_passages, field_name, id_key: "passage_id")
        return "missing or empty \"#{field_name}\" array" unless actual_passages.is_a?(Array) && actual_passages.any?

        actual_ids = actual_passages.map { |passage| passage[id_key] }
        return nil if actual_ids == expected_ids

        missing = expected_ids - actual_ids
        extra = actual_ids - expected_ids
        details = []
        details << "missing #{id_key}(s) #{missing.inspect}" if missing.any?
        details << "unexpected #{id_key}(s) #{extra.inspect}" if extra.any?
        details << "same ids but reordered/duplicated relative to prior step" if details.empty?

        "#{field_name} does not match expected #{id_key} sequence: #{details.join(', ')}"
      end

      # Review-only steps (factcheck, editor) don't reassemble anything, so this
      # is a set comparison, not an ordered one.
      def validate_set_coverage(expected_ids, actual_passages, field_name)
        return "missing or empty \"#{field_name}\" array" unless actual_passages.is_a?(Array) && actual_passages.any?

        actual_ids = actual_passages.map { |passage| passage["passage_id"] }
        missing = expected_ids - actual_ids
        extra = actual_ids - expected_ids
        return nil if missing.empty? && extra.empty?

        details = []
        details << "missing passage_id(s) #{missing.inspect}" if missing.any?
        details << "unexpected passage_id(s) #{extra.inspect}" if extra.any?
        "#{field_name} does not cover expected passage_id set: #{details.join(', ')}"
      end

      # A passage counts as flagged if any of its checks came back false, or if
      # it has findings a human should look at even when every check passed.
      # Shared by both factcheck and editor results — they use the identical
      # reviewed_passages/checks/findings shape.
      def count_flagged_passages(parsed)
        (parsed["reviewed_passages"] || []).count do |passage|
          checks = passage["checks"] || {}
          checks.values.any? { |value| value == false } || (passage["findings"] || []).any?
        end
      end

      # Enforces the two correctness properties: passage_id must be sequential
      # and in reading order (checked by requiring passage N's id to equal its
      # 1-based array index), and the segmentation must be exhaustive/non-
      # overlapping (checked by reconstructing the chapter from anchor_quote
      # concatenation). Whitespace-normalized on both sides — anchor_quote is
      # verbatim Korean text, not immune to incidental whitespace drift, and
      # that's not the property being tested here. Returns nil when
      # segmentation is sound, else a human-readable description of the
      # gap/overlap/id bug.
      def validate_segmentation(korean_text, parsed)
        passages = parsed["passages"]
        return "missing or empty \"passages\" array" unless passages.is_a?(Array) && passages.any?

        passages.each_with_index do |passage, index|
          expected_id = index + 1
          actual_id = passage["passage_id"]
          next if actual_id == expected_id

          return "passage_id out of order/non-sequential at array index #{index}: " \
                 "expected #{expected_id}, got #{actual_id.inspect}"
        end

        reconstructed = passages.map { |passage| passage["anchor_quote"].to_s }.join
        return nil if normalize_whitespace(reconstructed) == normalize_whitespace(korean_text)

        "anchor_quote concatenation does not reconstruct the source chapter " \
        "(gap or overlap in segmentation)"
      end

      def normalize_whitespace(text)
        text.to_s.gsub(/\s+/, "")
      end
    end
  end
end
