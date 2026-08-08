# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslateBatch::BeatSegmenter
#
# Pure Ruby, no LLM calls. Splits a decision that used to be one free-form
# LLM call (build_segmentation_system_prompt, now removed) into a
# deterministic/semantic hybrid, per docs/DECISIONS.md's hybrid beat
# segmentation entry: that free-form design's passage count was
# non-deterministic run-to-run on the identical chapter (52 -> 63 -> 93 ->
# 107 passages across four runs), because the model was inventing its own
# boundaries from scratch every time.
#
# .candidate_blocks does the deterministic half: groups the chapter's
# blank-line-delimited one-liners into small blocks of 3-7 lines, forcing a
# block boundary at every literal "***" scene marker (the only scene-break
# convention used across this novel's chapters) so the model is never asked
# to detect scene changes itself.
#
# .merge_beats does the other half of the hybrid: given the LLM's
# CONTINUE/BREAK/BRIDGE classification of each candidate block (relative to
# the block before it) plus a speaker attribution per block, deterministically
# merges blocks into final beats/passages. The model only ever answers a
# bounded per-block question; it never invents a boundary unprompted.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslateBatch
      module BeatSegmenter
        SCENE_BREAK_MARKER = "***"
        MIN_BLOCK_LINES = 3
        MAX_BLOCK_LINES = 7

        CandidateBlock = Data.define(:block_id, :text, :scene_break)

        def self.candidate_blocks(korean_text)
          lines = korean_text.split(/\n\s*\n+/).map(&:strip).reject(&:empty?)
          raw_blocks = []
          buffer = []

          flush = -> {
            unless buffer.empty?
              raw_blocks << { text: buffer.join("\n\n"), scene_break: false }
              buffer = []
            end
          }

          lines.each do |line|
            if line == SCENE_BREAK_MARKER
              flush.call
              raw_blocks << { text: line, scene_break: true }
              next
            end

            buffer << line
            flush.call if buffer.size >= MAX_BLOCK_LINES
          end
          flush.call

          merge_undersized_tail(raw_blocks).each_with_index.map do |raw, index|
            CandidateBlock.new(block_id: index + 1, text: raw[:text], scene_break: raw[:scene_break])
          end
        end

        # Blocks only ever fall under MIN_BLOCK_LINES as the last flush before a
        # scene break or end of chapter (the MAX_BLOCK_LINES cap always produces
        # exactly full-size blocks otherwise), so this only ever needs to look
        # backward one block. Merging into the previous block (rather than
        # leaving a 1-2 line orphan) trades an occasional oversized block for
        # never reproducing the free-form design's micro-passage problem.
        def self.merge_undersized_tail(raw_blocks)
          merged = []
          raw_blocks.each do |raw|
            previous = merged.last
            if !raw[:scene_break] && line_count(raw[:text]) < MIN_BLOCK_LINES && previous && !previous[:scene_break]
              merged[-1] = { text: "#{previous[:text]}\n\n#{raw[:text]}", scene_break: false }
            else
              merged << raw
            end
          end
          merged
        end
        private_class_method :merge_undersized_tail

        def self.line_count(text)
          text.split("\n\n").size
        end
        private_class_method :line_count

        # classified_blocks: parsed JSON entries shaped like
        # { "block_id" => 2, "speaker" => "string", "label" => "CONTINUE" }
        # (see PromptBuilder.build_beat_classification_system_prompt). Only
        # non-scene-break blocks appear here; scene_break blocks are handled
        # structurally below, never sent to the model.
        #
        # The label on the first block of each scene is always treated as
        # BREAK regardless of what the model returned — that boundary is
        # already structurally forced by candidate_blocks, so there's nothing
        # to trust the model's judgment on there.
        def self.merge_beats(candidate_blocks, classified_blocks)
          by_id = classified_blocks.to_h { |entry| [ entry["block_id"], entry ] }

          beats = []
          current = []
          bridge = []
          scene_started = false

          candidate_blocks.each do |candidate|
            if candidate.scene_break
              current = flush_bridge(bridge, current, beats)
              bridge = []
              beats << current unless current.empty?
              beats << [ candidate ]
              current = []
              scene_started = false
              next
            end

            label = scene_started ? by_id.dig(candidate.block_id, "label") : "BREAK"
            scene_started = true

            case label
            when "CONTINUE"
              if current.empty? && !bridge.empty?
                current = bridge
                bridge = []
              end
              current << candidate
            when "BRIDGE"
              beats << current unless current.empty?
              current = []
              bridge << candidate
            else # "BREAK", or an unrecognized/missing label - treat as BREAK
              beats << current unless current.empty?
              current = bridge + [ candidate ]
              bridge = []
            end
          end

          current = flush_bridge(bridge, current, beats)
          beats << current unless current.empty?

          beats.each_with_index.map { |blocks, index| to_passage(blocks, index + 1, by_id) }
        end

        # A BRIDGE block with no following beat to attach to (scene or chapter
        # ends right after it) falls back to attaching to the beat before it.
        def self.flush_bridge(bridge, current, beats)
          return current if bridge.empty?
          return current + bridge unless current.empty?

          if beats.empty?
            bridge
          else
            beats.last.concat(bridge)
            current
          end
        end
        private_class_method :flush_bridge

        def self.to_passage(blocks, passage_id, by_id)
          speakers = blocks.map { |block| block.scene_break ? "narration" : by_id.dig(block.block_id, "speaker") }
                           .compact.uniq
          {
            "passage_id" => passage_id,
            "speakers" => speakers,
            "anchor_quote" => blocks.map(&:text).join("\n\n"),
            # Every beat boundary sits exactly on a candidate_blocks boundary, and every
            # candidate_blocks boundary is, by construction of candidate_blocks' blank-line
            # split, a place the source Korean had a blank line — so this is a structural
            # fact about where beats come from, not a heuristic guess. True for every passage
            # except the chapter's first, which has nothing before it to break from.
            "paragraph_break_before" => passage_id > 1
          }
        end
        private_class_method :to_passage

        # Joins Step 3 (localization)'s per-passage translations into the final chapter text,
        # using Step 1's paragraph_break_before facts rather than trusting the model to have
        # reproduced source whitespace at passage boundaries on its own (docs/DECISIONS.md
        # 2026-07-31: naive concatenation was found to silently weld passages together with
        # zero separator). Looks passages up by passage_id rather than relying on matching
        # array order, so it stays correct even without a prior ordered-coverage check.
        def self.assemble_chapter_text(segmentation_passages:, localized_passages:)
          paragraph_break_by_id = segmentation_passages.to_h { |passage| [ passage["passage_id"], passage["paragraph_break_before"] ] }

          localized_passages.reduce(+"") do |text, passage|
            piece = passage["localized_translation"].to_s.strip
            next text if piece.empty?

            unless text.empty?
              # Defaulting a missing lookup to true is defensive, not currently reachable —
              # see paragraph_break_before's comment on to_passage.
              text << (paragraph_break_by_id.fetch(passage["passage_id"], true) ? "\n\n" : " ")
            end
            text << piece
          end
        end
      end
    end
  end
end
