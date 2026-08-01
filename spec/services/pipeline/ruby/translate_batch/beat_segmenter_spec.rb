require "rails_helper"

RSpec.describe Pipeline::Ruby::TranslateBatch::BeatSegmenter do
  describe ".candidate_blocks" do
    def block_texts(korean_text)
      described_class.candidate_blocks(korean_text).map(&:text)
    end

    def scene_breaks(korean_text)
      described_class.candidate_blocks(korean_text).map(&:scene_break)
    end

    it "groups a short scene (under the max) into a single block" do
      text = (1..5).map { |n| "line #{n}" }.join("\n\n")
      expect(block_texts(text)).to eq([ text ])
    end

    it "splits a scene into 7-line and 3-line blocks at 10 lines" do
      lines = (1..10).map { |n| "line #{n}" }
      text = lines.join("\n\n")
      blocks = described_class.candidate_blocks(text)
      expect(blocks.map { |b| b.text.split("\n\n").size }).to eq([ 7, 3 ])
    end

    it "merges an undersized trailing remainder into the previous block rather than leaving a 1-2 line block" do
      lines = (1..9).map { |n| "line #{n}" }
      text = lines.join("\n\n")
      blocks = described_class.candidate_blocks(text)
      expect(blocks.size).to eq(1)
      expect(blocks.first.text.split("\n\n").size).to eq(9)
    end

    it "assigns sequential block_id starting at 1" do
      lines = (1..10).map { |n| "line #{n}" }
      text = lines.join("\n\n")
      expect(described_class.candidate_blocks(text).map(&:block_id)).to eq([ 1, 2 ])
    end

    it "treats a literal *** line as its own scene_break block, forcing a boundary on both sides" do
      text = [ "line 1", "line 2", "***", "line 3", "line 4" ].join("\n\n")
      blocks = described_class.candidate_blocks(text)

      expect(blocks.map(&:text)).to eq([ "line 1\n\nline 2", "***", "line 3\n\nline 4" ])
      expect(scene_breaks(text)).to eq([ false, true, false ])
    end

    it "does not merge a 1-2 line remainder across a scene break into the marker block" do
      text = [ "a", "b", "***", "c" ].join("\n\n")
      blocks = described_class.candidate_blocks(text)
      expect(blocks.map(&:text)).to eq([ "a\n\nb", "***", "c" ])
    end

    it "reconstructs the full source text (whitespace-normalized) when blocks are concatenated" do
      text = [ "line 1", "line 2", "***", "line 3", "line 4", "line 5", "line 6", "line 7", "line 8", "line 9" ].join("\n\n")
      reconstructed = described_class.candidate_blocks(text).map(&:text).join
      expect(reconstructed.gsub(/\s+/, "")).to eq(text.gsub(/\s+/, ""))
    end

    it "ignores blank lines and stray whitespace between paragraphs" do
      text = "line 1\n\n\n\nline 2\n\n  \n\nline 3"
      expect(block_texts(text)).to eq([ "line 1\n\nline 2\n\nline 3" ])
    end
  end

  describe ".merge_beats" do
    def block(id, text, scene_break: false)
      described_class::CandidateBlock.new(block_id: id, text: text, scene_break: scene_break)
    end

    def classified(id, speaker:, label:)
      { "block_id" => id, "speaker" => speaker, "label" => label }
    end

    it "forces the first block of the chapter into its own beat regardless of the given label" do
      blocks = [ block(1, "hello") ]
      classifications = [ classified(1, speaker: "narration", label: "CONTINUE") ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages).to eq([
        { "passage_id" => 1, "speakers" => [ "narration" ], "anchor_quote" => "hello" }
      ])
    end

    it "merges consecutive CONTINUE blocks into one beat, deduping repeated speakers in order" do
      blocks = [ block(1, "one"), block(2, "two"), block(3, "three") ]
      classifications = [
        classified(1, speaker: "정한", label: "BREAK"),
        classified(2, speaker: "정한", label: "CONTINUE"),
        classified(3, speaker: "희연", label: "CONTINUE")
      ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages).to eq([
        { "passage_id" => 1, "speakers" => [ "정한", "희연" ], "anchor_quote" => "one\n\ntwo\n\nthree" }
      ])
    end

    it "starts a new beat on BREAK" do
      blocks = [ block(1, "one"), block(2, "two") ]
      classifications = [
        classified(1, speaker: "narration", label: "BREAK"),
        classified(2, speaker: "정한", label: "BREAK")
      ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages.map { |p| p["anchor_quote"] }).to eq([ "one", "two" ])
      expect(passages.map { |p| p["passage_id"] }).to eq([ 1, 2 ])
    end

    it "attaches a BRIDGE block to the beat that follows it" do
      blocks = [ block(1, "one"), block(2, "bridge"), block(3, "three") ]
      classifications = [
        classified(1, speaker: "narration", label: "BREAK"),
        classified(2, speaker: "narration", label: "BRIDGE"),
        classified(3, speaker: "정한", label: "CONTINUE")
      ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages.map { |p| p["anchor_quote"] }).to eq([ "one", "bridge\n\nthree" ])
    end

    it "attaches a BRIDGE block that starts the next beat (labeled BREAK) to that following beat" do
      blocks = [ block(1, "one"), block(2, "bridge"), block(3, "three") ]
      classifications = [
        classified(1, speaker: "narration", label: "BREAK"),
        classified(2, speaker: "narration", label: "BRIDGE"),
        classified(3, speaker: "정한", label: "BREAK")
      ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages.map { |p| p["anchor_quote"] }).to eq([ "one", "bridge\n\nthree" ])
    end

    it "falls back to attaching a trailing BRIDGE to the preceding beat when the scene ends right after it" do
      blocks = [ block(1, "one"), block(2, "bridge"), block(3, "***", scene_break: true) ]
      classifications = [
        classified(1, speaker: "narration", label: "BREAK"),
        classified(2, speaker: "narration", label: "BRIDGE")
      ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages.map { |p| p["anchor_quote"] }).to eq([ "one\n\nbridge", "***" ])
    end

    it "gives a scene-break block its own beat with speaker narration" do
      blocks = [ block(1, "one"), block(2, "***", scene_break: true), block(3, "two") ]
      classifications = [
        classified(1, speaker: "정한", label: "BREAK"),
        classified(3, speaker: "희연", label: "BREAK")
      ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages).to eq([
        { "passage_id" => 1, "speakers" => [ "정한" ], "anchor_quote" => "one" },
        { "passage_id" => 2, "speakers" => [ "narration" ], "anchor_quote" => "***" },
        { "passage_id" => 3, "speakers" => [ "희연" ], "anchor_quote" => "two" }
      ])
    end

    it "forces the first block after a scene break into its own beat regardless of the given label" do
      blocks = [ block(1, "one"), block(2, "***", scene_break: true), block(3, "two"), block(4, "three") ]
      classifications = [
        classified(1, speaker: "narration", label: "BREAK"),
        classified(3, speaker: "희연", label: "CONTINUE"),
        classified(4, speaker: "희연", label: "CONTINUE")
      ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages.map { |p| p["anchor_quote"] }).to eq([ "one", "***", "two\n\nthree" ])
    end

    it "assigns sequential passage_id across the whole chapter" do
      blocks = [ block(1, "one"), block(2, "***", scene_break: true), block(3, "two") ]
      classifications = [
        classified(1, speaker: "narration", label: "BREAK"),
        classified(3, speaker: "희연", label: "BREAK")
      ]

      passages = described_class.merge_beats(blocks, classifications)

      expect(passages.map { |p| p["passage_id"] }).to eq([ 1, 2, 3 ])
    end
  end
end
