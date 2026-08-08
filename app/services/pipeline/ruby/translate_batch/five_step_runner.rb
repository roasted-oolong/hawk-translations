require "json"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslateBatch::FiveStepRunner
#
# Owns exactly one responsibility: call the 5-step translation pipeline
# (hybrid beat segmentation -> analysis -> localization -> {factcheck,
# editor}) for one chapter and validate each step's output. No file I/O, no
# knowledge of TranslationJob/Chapter/output directories — callers own all
# of that. Extracted from Pipeline::Ruby::TranslationEval (the original,
# offline-only home of this chain) so the same step logic can be shared with
# production Pipeline::Ruby::TranslateBatch without duplicating it.
#
# The chain is strict: segmentation -> analysis -> localization -> {factcheck,
# editor}. Each step only runs when the step(s) it depends on produced valid,
# fully-covered output — there's nothing trustworthy to chain into otherwise.
# factcheck and editor both depend only on localization, not on each other;
# they're independent QA passes.
#
# factcheck/editor are opt-in per call via run_chapter's run_qa: — production
# TranslateBatch passes run_qa: false (see docs/DECISIONS.md): those two
# steps never run there, and the pre-existing, separately-prompted Chapter QA
# feature (chapter_qa.rb) is the supported way to get a factcheck/editor pass
# on a chapter's translation. TranslationEval keeps the default run_qa: true
# since the offline harness exists to validate all 5 steps together.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslateBatch
      class FiveStepRunner
        # Uniform per-step result. call_error stays a formatted
        # "#{category}: #{message}" string (existing TranslationEval spec
        # assertions check this exact shape). error_category/error_message
        # carry the raw Pipeline::ClaudeCode::Result values (nil unless this
        # step's own call failed) — production TranslateBatch needs the raw
        # category to bucket into RECOVERABLE_CATEGORIES/FATAL_CATEGORIES;
        # TranslationEval doesn't need them. raw_output is only set when a
        # call succeeded but its output failed to parse as JSON, so a caller
        # can save it for a human to inspect.
        StepOutcome = Data.define(:call_error, :error_category, :error_message,
                                   :valid_json, :coverage_error, :parsed, :raw_output) do
          def ok?
            call_error.nil? && valid_json && coverage_error.nil?
          end
        end

        # classification is Step 1's pre-merge LLM hash ({"blocks"=>[...]}),
        # kept only so TranslationEval can still dump classification.json —
        # production has no use for it. assembled_text is non-nil only when
        # localization succeeded with full coverage (see BeatSegmenter.assemble_chapter_text).
        # factcheck/editor are nil (not a skipped StepOutcome) when run_chapter
        # was called with run_qa: false — nil means "not run at all", distinct
        # from a StepOutcome saying a dependency failed.
        ChapterOutcome = Data.define(:number, :classification, :segmentation, :analysis,
                                      :localization, :factcheck, :editor, :assembled_text)

        def self.build_for_novel(novel_dir:, novel_directory_name:, config:)
          reference_data   = PromptBuilder.load_reference_files(novel_dir)
          narrator_note    = PromptBuilder.extract_narrator_note(reference_data[:novel_info])
          context          = PromptBuilder::TranslationContext.new(**reference_data, narrator_note: narrator_note)
          cultural_patterns = read_cultural_patterns(novel_dir)

          new(
            segmentation_prompt: PromptBuilder.build_beat_classification_system_prompt(context),
            analysis_prompt:     PromptBuilder.build_analysis_system_prompt(context, cultural_patterns: cultural_patterns),
            localization_prompt: PromptBuilder.build_localization_system_prompt(context, cultural_patterns: cultural_patterns),
            factcheck_prompt:    PromptBuilder.build_factcheck_system_prompt(context, cultural_patterns: cultural_patterns),
            editor_prompt:       PromptBuilder.build_editor_system_prompt,
            mcp_config: BridgeConfig.mcp_config(novel_directory_name: novel_directory_name),
            config: config
          )
        end

        # A passage counts as flagged if any of its checks came back false, or
        # if it has findings a human should look at even when every check
        # passed. Shared by both factcheck and editor results — they use the
        # identical reviewed_passages/checks/findings shape.
        def self.count_flagged_passages(parsed)
          (parsed["reviewed_passages"] || []).count do |passage|
            checks = passage["checks"] || {}
            checks.values.any? { |value| value == false } || (passage["findings"] || []).any?
          end
        end

        def self.read_cultural_patterns(novel_dir)
          path = File.join(novel_dir, "bible", "cultural_patterns.md")
          File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
        end
        private_class_method :read_cultural_patterns

        def initialize(segmentation_prompt:, analysis_prompt:, localization_prompt:,
                        factcheck_prompt:, editor_prompt:, mcp_config:, config:)
          @segmentation_prompt = segmentation_prompt
          @analysis_prompt     = analysis_prompt
          @localization_prompt = localization_prompt
          @factcheck_prompt    = factcheck_prompt
          @editor_prompt       = editor_prompt
          @mcp_config          = mcp_config
          @config              = config
        end

        def run_chapter(number, korean_text, run_qa: true)
          classification, segmentation = run_segmentation(korean_text)

          analysis = segmentation.ok? ? run_analysis(segmentation.parsed) :
            skip_step("skipped: segmentation did not produce valid, fully-covered passages")

          localization = analysis.ok? ? run_localization(segmentation.parsed, analysis.parsed) :
            skip_step("skipped: analysis did not produce valid, fully-covered output")

          factcheck, editor = qa_steps(run_qa, segmentation, analysis, localization)

          assembled_text = localization.ok? ?
            BeatSegmenter.assemble_chapter_text(
              segmentation_passages: segmentation.parsed["passages"],
              localized_passages: localization.parsed["localized_passages"]
            ) : nil

          ChapterOutcome.new(
            number: number, classification: classification, segmentation: segmentation,
            analysis: analysis, localization: localization, factcheck: factcheck, editor: editor,
            assembled_text: assembled_text
          )
        end

        private

        # nil/nil when run_qa: false — factcheck/editor never get called at
        # all in that mode, not merely skipped-and-recorded.
        def qa_steps(run_qa, segmentation, analysis, localization)
          return [ nil, nil ] unless run_qa
          return [ run_factcheck(segmentation.parsed, analysis.parsed, localization.parsed), run_editor(localization.parsed) ] if localization.ok?

          skipped = skip_step("skipped: localization did not produce valid, fully-covered translation")
          [ skipped, skipped ]
        end

        def skip_step(message)
          StepOutcome.new(call_error: message, error_category: nil, error_message: nil,
                           valid_json: nil, coverage_error: nil, parsed: nil, raw_output: nil)
        end

        def call_failure(result)
          StepOutcome.new(
            call_error: "#{result.error_category}: #{result.error_message}",
            error_category: result.error_category, error_message: result.error_message,
            valid_json: nil, coverage_error: nil, parsed: nil, raw_output: nil
          )
        end

        def invalid_json(result, error)
          StepOutcome.new(
            call_error: "invalid JSON (#{error.message})", error_category: nil, error_message: nil,
            valid_json: false, coverage_error: nil, parsed: nil, raw_output: result.output
          )
        end

        # Step 1. Hybrid segmentation: BeatSegmenter.candidate_blocks
        # deterministically pre-chunks the chapter (no LLM call), one LLM call
        # classifies each block's relationship to the block before it, then
        # BeatSegmenter.merge_beats deterministically assembles the final
        # passages (no LLM call). Coverage here checks that every candidate
        # block got exactly one classification, in order; once merged, the
        # same anchor_quote-reconstruction check as before still applies to
        # the final passages. Returns [classification_hash_or_nil, StepOutcome].
        def run_segmentation(korean_text)
          candidate_blocks = BeatSegmenter.candidate_blocks(korean_text)
          classifiable_ids = candidate_blocks.reject(&:scene_break).map(&:block_id)

          user_message = PromptBuilder.build_beat_classification_user_message(candidate_blocks: candidate_blocks)
          result = Pipeline::ClaudeCode.call(
            system_prompt: @segmentation_prompt, user_message: user_message, config: @config, mcp_config: @mcp_config
          )
          return [ nil, call_failure(result) ] unless result.success?

          begin
            classification = JSON.parse(result.output)
          rescue JSON::ParserError => e
            return [ nil, invalid_json(result, e) ]
          end

          coverage_error = validate_ordered_coverage(classifiable_ids, classification["blocks"], "blocks", id_key: "block_id")
          if coverage_error
            return [ classification, StepOutcome.new(call_error: nil, error_category: nil, error_message: nil,
                                                       valid_json: true, coverage_error: coverage_error, parsed: nil, raw_output: nil) ]
          end

          parsed = { "passages" => BeatSegmenter.merge_beats(candidate_blocks, classification["blocks"]) }
          [ classification, StepOutcome.new(call_error: nil, error_category: nil, error_message: nil,
                                             valid_json: true, coverage_error: validate_segmentation(korean_text, parsed),
                                             parsed: parsed, raw_output: nil) ]
        end

        # Step 2. Consumes Step 1's segmentation. Ordered coverage, since
        # Step 3 needs the same passage_id sequence to chain from.
        def run_analysis(segmentation_parsed)
          user_message = PromptBuilder.build_analysis_user_message(segmentation_result: segmentation_parsed)
          result = Pipeline::ClaudeCode.call(
            system_prompt: @analysis_prompt, user_message: user_message, config: @config, mcp_config: @mcp_config
          )
          return call_failure(result) unless result.success?

          begin
            parsed = JSON.parse(result.output)
          rescue JSON::ParserError => e
            return invalid_json(result, e)
          end

          expected_ids = (segmentation_parsed["passages"] || []).map { |passage| passage["passage_id"] }
          coverage_error = validate_ordered_coverage(expected_ids, parsed["passages"], "passages")
          StepOutcome.new(call_error: nil, error_category: nil, error_message: nil,
                          valid_json: true, coverage_error: coverage_error, parsed: parsed, raw_output: nil)
        end

        # Step 3. Consumes Step 1's segmentation (for passage_id/paragraph
        # break facts) and Step 2's analysis. Ordered coverage, since
        # reassembly depends on knowing every passage_id is present.
        def run_localization(segmentation_parsed, analysis_parsed)
          user_message = PromptBuilder.build_localization_user_message(
            segmentation_result: segmentation_parsed, analysis_result: analysis_parsed
          )
          result = Pipeline::ClaudeCode.call(
            system_prompt: @localization_prompt, user_message: user_message, config: @config, mcp_config: @mcp_config
          )
          return call_failure(result) unless result.success?

          begin
            parsed = JSON.parse(result.output)
          rescue JSON::ParserError => e
            return invalid_json(result, e)
          end

          expected_ids = (analysis_parsed["passages"] || []).map { |passage| passage["passage_id"] }
          coverage_error = validate_ordered_coverage(expected_ids, parsed["localized_passages"], "localized_passages")
          StepOutcome.new(call_error: nil, error_category: nil, error_message: nil,
                          valid_json: true, coverage_error: coverage_error, parsed: parsed, raw_output: nil)
        end

        # Step 4. Independently checks names/facts/cultural cues survived into
        # Step 3's translation — not prose quality, that's Step 5. Runs on
        # @config.factcheck_model rather than translation_model — this is a
        # verification task, not creative generation, so a cheaper model is
        # expected to hold up.
        def run_factcheck(segmentation_parsed, analysis_parsed, localization_parsed)
          user_message = PromptBuilder.build_factcheck_user_message(
            segmentation_result: segmentation_parsed, analysis_result: analysis_parsed, localization_result: localization_parsed
          )
          result = Pipeline::ClaudeCode.call(
            system_prompt: @factcheck_prompt, user_message: user_message, config: @config,
            mcp_config: @mcp_config, model: @config.factcheck_model
          )
          return call_failure(result) unless result.success?

          begin
            parsed = JSON.parse(result.output)
          rescue JSON::ParserError => e
            return invalid_json(result, e)
          end

          expected_ids = (localization_parsed["localized_passages"] || []).map { |passage| passage["passage_id"] }
          coverage_error = validate_set_coverage(expected_ids, parsed["reviewed_passages"], "reviewed_passages")
          StepOutcome.new(call_error: nil, error_category: nil, error_message: nil,
                          valid_json: true, coverage_error: coverage_error, parsed: parsed, raw_output: nil)
        end

        # Step 5. Reviews ONLY Step 3's English text — no Korean, no analysis
        # (see build_editor_user_message/build_editor_system_prompt).
        def run_editor(localization_parsed)
          user_message = PromptBuilder.build_editor_user_message(localization_result: localization_parsed)
          result = Pipeline::ClaudeCode.call(
            system_prompt: @editor_prompt, user_message: user_message, config: @config, mcp_config: @mcp_config
          )
          return call_failure(result) unless result.success?

          begin
            parsed = JSON.parse(result.output)
          rescue JSON::ParserError => e
            return invalid_json(result, e)
          end

          expected_ids = (localization_parsed["localized_passages"] || []).map { |passage| passage["passage_id"] }
          coverage_error = validate_set_coverage(expected_ids, parsed["reviewed_passages"], "reviewed_passages")
          StepOutcome.new(call_error: nil, error_category: nil, error_message: nil,
                          valid_json: true, coverage_error: coverage_error, parsed: parsed, raw_output: nil)
        end

        # Reassembly downstream (Step 3) depends on every id being present, so
        # expected_ids and actual_ids must match exactly, not just as sets.
        # id_key defaults to "passage_id" but Step 1's classification coverage
        # check keys on "block_id" instead.
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

        # Review-only steps (factcheck, editor) don't reassemble anything, so
        # this is a set comparison, not an ordered one.
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

        # Enforces the two correctness properties: passage_id must be
        # sequential and in reading order (checked by requiring passage N's id
        # to equal its 1-based array index), and the segmentation must be
        # exhaustive/non-overlapping (checked by reconstructing the chapter
        # from anchor_quote concatenation). Whitespace-normalized on both
        # sides — anchor_quote is verbatim Korean text, not immune to
        # incidental whitespace drift, and that's not the property being
        # tested here. Returns nil when segmentation is sound, else a
        # human-readable description of the gap/overlap/id bug.
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
end
