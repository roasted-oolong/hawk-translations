# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslateBatch::TitleFinalizer
#
# Production translate_batch's third call, run immediately after FeelCheck
# for the same chapter — see docs/DECISIONS.md's 2026-08-08 title-last
# entry. build_system_prompt's one-shot translation writes the chapter title
# first, as the literal first tokens of its output, before it has translated
# a single line of the body — so the title's wording gets locked in before
# any of the body's specific word choices, phrasing, or motifs exist to draw
# on. This call replaces that draft title with one translated against the
# *finished* English body (post-FeelCheck), so it can actually echo
# something the translation landed on.
#
# Splits both the Korean source and the current English text on their first
# blank line (the same paragraph convention BeatSegmenter.candidate_blocks
# already treats as structural) to get "title" vs. "everything else" without
# an LLM call, then asks one small call to translate just the title with the
# finished body as context, then swaps it back in.
#
# Failure here degrades, it doesn't fail the chapter — same discipline as
# FeelCheck: the draft title from build_system_prompt is a perfectly
# publishable title on its own, just a less-informed one. Losing this pass
# isn't grounds to drop the chapter or leave it title-less.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslateBatch
      class TitleFinalizer
        Result = Struct.new(:text, :error_category, :error_message, keyword_init: true) do
          def ok?
            error_category.nil?
          end
        end

        def self.call(korean_text:, english_text:, config:, mcp_config: nil)
          new(korean_text: korean_text, english_text: english_text, config: config, mcp_config: mcp_config).call
        end

        def initialize(korean_text:, english_text:, config:, mcp_config:)
          @korean_text  = korean_text
          @english_text = english_text
          @config       = config
          @mcp_config   = mcp_config
        end

        def call
          korean_title, _korean_body = split_title(@korean_text)
          draft_title, body = split_title(@english_text)
          # No blank line in either text means there's no separable title
          # line to begin with — nothing to finalize, not a failure.
          return Result.new(text: @english_text) if korean_title.empty? || draft_title.empty? || body.empty?

          result = Pipeline::ClaudeCode.call(
            system_prompt: PromptBuilder.build_title_finalize_system_prompt,
            user_message:  PromptBuilder.build_title_finalize_user_message(
              korean_title: korean_title, draft_title: draft_title, english_body: body
            ),
            config:     @config,
            mcp_config: @mcp_config,
            model:      @config.translation_model
          )
          return degrade(result.error_category, "#{result.error_category}: #{result.error_message}") unless result.success?

          final_title = result.output.to_s.strip
          return degrade(:empty_title, "model returned an empty title") if final_title.empty?

          Result.new(text: "#{final_title}\n\n#{body}")
        end

        private

        # Returns ["", ""] when there's no blank line at all, so callers can
        # tell "no separable title" apart from a real (possibly one-word)
        # title followed by a body — string_a.empty? is truthy either way,
        # but only the no-blank-line case should ever produce both empty.
        def split_title(text)
          parts = text.to_s.split(/\n\s*\n+/, 2)
          return [ "", "" ] unless parts.size == 2
          [ parts[0].strip, parts[1] ]
        end

        def degrade(error_category, error_message)
          Result.new(text: @english_text, error_category: error_category || :title_finalize_error, error_message: error_message)
        end
      end
    end
  end
end
