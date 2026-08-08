require "json"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslateBatch::FeelCheck
#
# Production translate_batch's second call, run immediately after
# PromptBuilder.build_system_prompt's translation for the same chapter.
# Chunks the English translation into segments (BeatSegmenter.candidate_blocks
# — pure Ruby, no LLM call, language-agnostic: blank-line paragraph grouping
# into 3-7 line blocks, forced boundary at every "***" scene marker), asks one
# Claude call to judge each segment's naturalness and rewrite any that don't
# read well, then reassembles the chapter with rewrites substituted in.
# Scene-marker blocks are never sent to the model (nothing to judge) and are
# always kept as-is on reassembly, same discipline BeatSegmenter's own
# classification call already uses.
#
# Deliberately not modeled on FiveStepRunner's StepOutcome — this needs none
# of that class's ordered-vs-set coverage split or gating-vs-QA distinction,
# just a call/parse/validate/reassemble sequence for one step.
#
# Failure here degrades, it doesn't fail the chapter: the translation call
# already succeeded and is publishable on its own; losing the polish pass
# isn't grounds to drop a chapter translate_batch otherwise produced cleanly.
# .call always returns a usable `text` — callers that want to know whether a
# rewrite pass actually ran can check `ok?`/`error_message`.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslateBatch
      class FeelCheck
        Result = Struct.new(:text, :error_category, :error_message, :rewritten_count, keyword_init: true) do
          def ok?
            error_category.nil?
          end
        end

        def self.call(english_text:, config:, mcp_config: nil)
          new(english_text: english_text, config: config, mcp_config: mcp_config).call
        end

        def initialize(english_text:, config:, mcp_config:)
          @english_text = english_text
          @config       = config
          @mcp_config   = mcp_config
        end

        def call
          blocks = BeatSegmenter.candidate_blocks(@english_text)
          reviewable = blocks.reject(&:scene_break)
          return Result.new(text: @english_text, rewritten_count: 0) if reviewable.empty?

          result = Pipeline::ClaudeCode.call(
            system_prompt: PromptBuilder.build_feel_check_system_prompt,
            user_message:  PromptBuilder.build_feel_check_user_message(segments: user_segments(reviewable)),
            config:        @config,
            mcp_config:    @mcp_config,
            model:         @config.translation_model
          )
          return degrade(result.error_category, "#{result.error_category}: #{result.error_message}") unless result.success?

          begin
            parsed = JSON.parse(result.output)
          rescue JSON::ParserError => e
            return degrade(:unparseable_output, "invalid JSON (#{e.message})")
          end

          segments_by_id = (parsed["segments"] || []).to_h { |segment| [ segment["segment_id"], segment ] }
          missing = reviewable.map(&:block_id) - segments_by_id.keys
          return degrade(nil, "coverage error: missing segment_id(s) #{missing.inspect}") if missing.any?

          reassemble(blocks, segments_by_id)
        end

        private

        def user_segments(reviewable_blocks)
          reviewable_blocks.map { |block| { "segment_id" => block.block_id, "text" => block.text } }
        end

        def reassemble(blocks, segments_by_id)
          rewritten_count = 0

          text = blocks.map do |block|
            next block.text if block.scene_break

            segment = segments_by_id.fetch(block.block_id)
            rewrite = segment["rewritten_text"].to_s.strip
            if segment["reads_naturally"] == false && rewrite.present?
              rewritten_count += 1
              rewrite
            else
              block.text
            end
          end.join("\n\n")

          Result.new(text: text, rewritten_count: rewritten_count)
        end

        # Always keeps the original translation — a feel-check failure means
        # the polish pass didn't run, not that the chapter failed.
        def degrade(error_category, error_message)
          Result.new(text: @english_text, error_category: error_category || :coverage_error, error_message: error_message, rewritten_count: 0)
        end
      end
    end
  end
end
