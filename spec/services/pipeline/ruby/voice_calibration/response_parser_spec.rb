require "rails_helper"

RSpec.describe Pipeline::Ruby::VoiceCalibration::ResponseParser do
  describe ".parse" do
    it "parses new pattern and retirement cards with the exact field names shipped consumers depend on" do
      raw = <<~RESP
        === NEW PATTERNS ===
        ## Passage 3 — Overwrought internal monologue
        *Chapter 7*

        > He felt the weight of a thousand years pressing on his chest.

        **What it demonstrates:** The narrator over-explains emotion.

        **What the wrong version looks like:** A flat, literal translation.

        **The rule it demonstrates:** Trust implication over explanation.

        ---

        === RETIREMENTS ===
        **Retirement candidate — Passage 1 — Existing pattern**

        Reason: Superseded by Passage 3 above.
        Superseded by: New Pattern 1 above
      RESP

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.cards.length).to eq(2)

      new_pattern = result.cards.find { |c| c.is_a?(described_class::NewPatternCard) }
      expect(new_pattern.to_card_hash).to eq(
        "id" => "new_pattern_0", "card_type" => "new_pattern",
        "heading" => "Passage 3 — Overwrought internal monologue",
        "chapter_ref" => "Chapter 7",
        "quote" => "He felt the weight of a thousand years pressing on his chest.",
        "what_it_demonstrates" => "The narrator over-explains emotion.",
        "wrong_version" => "A flat, literal translation.",
        "rule" => "Trust implication over explanation."
      )

      retirement = result.cards.find { |c| c.is_a?(described_class::RetirementCard) }
      expect(retirement.to_card_hash).to eq(
        "id" => "retirement_0", "card_type" => "retirement",
        "heading" => "Passage 1 — Existing pattern",
        "reason" => "Superseded by Passage 3 above."
      )
    end

    it "carries no decision key at generation time — calibrate-voice.py's own output never had one" do
      raw = "=== NEW PATTERNS ===\n## Passage 1 — X\n*Chapter 1*\n\n> quote\n\n**The rule it demonstrates:** rule\n\n=== RETIREMENTS ===\nNOTHING TO REPORT\n"
      result = described_class.parse(raw)
      expect(result.cards.first.to_card_hash).not_to have_key("decision")
    end

    it "treats NOTHING TO REPORT sections as legitimately empty" do
      raw = "=== NEW PATTERNS ===\nNOTHING TO REPORT\n\n=== RETIREMENTS ===\nNOTHING TO REPORT\n"
      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.cards).to be_empty
    end

    it "fails closed when the response has neither section marker" do
      result = described_class.parse("unstructured prose")
      expect(result).not_to be_success
      expect(result.failure_reason).to eq(:missing_markers)
    end

    it "drops a retirement block missing a Reason line" do
      raw = "=== NEW PATTERNS ===\nNOTHING TO REPORT\n\n=== RETIREMENTS ===\n**Retirement candidate — Passage 1**\n\nNo reason line here.\n"
      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.cards).to be_empty
    end
  end
end
