require "fileutils"
require "json"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslationEval
#
# Offline-only prototype harness for the translation quality pipeline idea
# in docs/ROADMAP.md — runs the existing single-pass prompt, the (now
# superseded, kept for history) single-call structured prompt, and the
# committed 2-call pipeline (docs/DECISIONS.md's 2026-07-30/2026-07-31
# entries) over the same chapters, writing all outputs to disk for a human
# to compare. Not wired into translate_batch.rb, PipelineJob, or any
# TranslationJob: the point is to judge quality/cost/JSON-reliability —
# segmentation exhaustiveness for Call 1, passage_id coverage for Call 2 —
# before committing to any change in production behavior. Driven by
# bin/translation_eval.
#
# Call 2 only runs when Call 1 produced valid, cleanly-segmented JSON —
# there's no analysis to chain from otherwise.
#
# Takes a plain novel directory rather than a Novel record — this runs
# outside the job system entirely, against chapters already on disk.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslationEval
      ChapterResult = Struct.new(
        :number, :missing_source, :single_pass_error, :structured_error, :structured_valid_json,
        :call1_error, :call1_valid_json, :call1_segmentation_error,
        :call2_error, :call2_valid_json, :call2_coverage_error,
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
        single_pass_prompt     = TranslateBatch::PromptBuilder.build_system_prompt(context)
        structured_prompt      = TranslateBatch::PromptBuilder.build_structured_system_prompt(context, cultural_patterns: read_cultural_patterns)
        call1_prompt            = TranslateBatch::PromptBuilder.build_call1_system_prompt(context, cultural_patterns: read_cultural_patterns)
        call2_prompt            = TranslateBatch::PromptBuilder.build_call2_system_prompt(context, cultural_patterns: read_cultural_patterns)
        mcp_config              = TranslateBatch::BridgeConfig.mcp_config(novel_directory_name: File.basename(@novel_dir))

        @chapter_numbers.map { |num| run_chapter(num, single_pass_prompt, structured_prompt, call1_prompt, call2_prompt, mcp_config) }
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

      def run_chapter(num, single_pass_prompt, structured_prompt, call1_prompt, call2_prompt, mcp_config)
        korean_path = File.join(@chapters_dir, "Chapter #{num} (Korean).txt")
        return ChapterResult.new(number: num, missing_source: true) unless File.exist?(korean_path)

        korean_text = File.read(korean_path, encoding: "UTF-8")
        chapter_dir = File.join(@output_dir, "chapter_#{num}")
        FileUtils.mkdir_p(chapter_dir)

        single_pass_error = run_single_pass(chapter_dir, single_pass_prompt, korean_text, mcp_config)
        structured_error, structured_valid_json = run_structured(chapter_dir, structured_prompt, korean_text, mcp_config)
        call1_error, call1_valid_json, call1_segmentation_error, call1_parsed =
          run_call1(chapter_dir, call1_prompt, korean_text, mcp_config)

        call2_error, call2_valid_json, call2_coverage_error =
          if call1_error.nil? && call1_valid_json && call1_segmentation_error.nil?
            run_call2(chapter_dir, call2_prompt, korean_text, call1_parsed, mcp_config)
          else
            [ "skipped: Call 1 did not produce valid, cleanly-segmented analysis", nil, nil ]
          end

        ChapterResult.new(
          number: num, missing_source: false,
          single_pass_error: single_pass_error,
          structured_error: structured_error,
          structured_valid_json: structured_valid_json,
          call1_error: call1_error,
          call1_valid_json: call1_valid_json,
          call1_segmentation_error: call1_segmentation_error,
          call2_error: call2_error,
          call2_valid_json: call2_valid_json,
          call2_coverage_error: call2_coverage_error
        )
      end

      def run_single_pass(chapter_dir, system_prompt, korean_text, mcp_config)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: korean_text, config: @config, mcp_config: mcp_config
        )
        return "#{result.error_category}: #{result.error_message}" unless result.success?

        File.write(File.join(chapter_dir, "single_pass.txt"), result.output, encoding: "UTF-8")
        nil
      end

      def run_structured(chapter_dir, system_prompt, korean_text, mcp_config)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: korean_text, config: @config, mcp_config: mcp_config
        )
        return [ "#{result.error_category}: #{result.error_message}", nil ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "structured.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false ]
        end

        File.write(File.join(chapter_dir, "structured.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")
        [ nil, true ]
      end

      # Returns [call_error, valid_json, segmentation_error, parsed]. Segmentation
      # is only checked once the response is valid JSON — it's the thing this
      # eval exists to validate per the 2026-07-30 decision's shipping
      # sequence (Call 1 first, checked against real chapters, before Call 2
      # gets built). `parsed` is returned regardless of the segmentation
      # result so callers can decide whether it's trustworthy enough to chain
      # into Call 2.
      def run_call1(chapter_dir, system_prompt, korean_text, mcp_config)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: korean_text, config: @config, mcp_config: mcp_config
        )
        return [ "#{result.error_category}: #{result.error_message}", nil, nil, nil ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "call1.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false, nil, nil ]
        end

        File.write(File.join(chapter_dir, "call1.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")
        [ nil, true, validate_segmentation(korean_text, parsed), parsed ]
      end

      # Chains Call 1's analysis into Call 2 (docs/DECISIONS.md's 2026-07-31
      # entry) and reassembles the result into a full chapter for direct
      # review. Returns [call_error, valid_json, coverage_error].
      def run_call2(chapter_dir, system_prompt, korean_text, call1_parsed, mcp_config)
        user_message = TranslateBatch::PromptBuilder.build_call2_user_message(
          korean_text: korean_text, call1_analysis: call1_parsed
        )
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: user_message, config: @config, mcp_config: mcp_config
        )
        return [ "#{result.error_category}: #{result.error_message}", nil, nil ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "call2.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false, nil ]
        end

        File.write(File.join(chapter_dir, "call2.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")

        coverage_error = validate_call2_coverage(call1_parsed, parsed)
        if coverage_error.nil?
          reassembled = parsed["localized_passages"].map { |passage| passage["localized_translation"].to_s }.join
          File.write(File.join(chapter_dir, "localized_chapter.txt"), reassembled, encoding: "UTF-8")
        end

        [ nil, true, coverage_error ]
      end

      # Call 2 is told to echo Call 1's passage_id rather than re-segment
      # (docs/DECISIONS.md's 2026-07-31 entry) — so "validate against the
      # source" here means checking localized_passages covers exactly the
      # same passage_id sequence Call 1 already validated against the
      # source, in the same order (reassembly is a straight concatenation,
      # so order matters as much as coverage).
      def validate_call2_coverage(call1_parsed, call2_parsed)
        expected_ids = (call1_parsed["passages"] || []).map { |passage| passage["passage_id"] }
        localized = call2_parsed["localized_passages"]
        return "missing or empty \"localized_passages\" array" unless localized.is_a?(Array) && localized.any?

        actual_ids = localized.map { |passage| passage["passage_id"] }
        return nil if actual_ids == expected_ids

        missing = expected_ids - actual_ids
        extra = actual_ids - expected_ids
        details = []
        details << "missing passage_id(s) #{missing.inspect}" if missing.any?
        details << "unexpected passage_id(s) #{extra.inspect}" if extra.any?
        details << "same ids but reordered/duplicated relative to Call 1" if details.empty?

        "localized_passages does not match Call 1's passage_id sequence: #{details.join(', ')}"
      end

      # Enforces the two correctness properties named in the 2026-07-30
      # decision doc: passage_id must be sequential and in reading order
      # (checked by requiring passage N's id to equal its 1-based array
      # index — sequential and ordered in one comparison), and the
      # segmentation must be exhaustive/non-overlapping (checked by
      # reconstructing the chapter from anchor_quote concatenation).
      # Whitespace-normalized on both sides — anchor_quote is verbatim
      # Korean text, not immune to incidental whitespace drift, and that's
      # not the property being tested here. Returns nil when segmentation is
      # sound, else a human-readable description of the gap/overlap/id bug.
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
