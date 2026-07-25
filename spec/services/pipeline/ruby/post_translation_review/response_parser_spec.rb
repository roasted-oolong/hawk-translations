require "rails_helper"

RSpec.describe Pipeline::Ruby::PostTranslationReview::ResponseParser do
  describe ".parse" do
    it "parses new entries, proposed edits, and story updates into typed cards" do
      raw = <<~RESP
        === NEW ENTRIES ===
        ### characters.md
        ## Kim Min-jun (김민준) — English
        - Korean name: 김민준
        - Role: protagonist

        ### locations.md
        ## Seoul Tower — English
        - Significance: meeting point

        === PROPOSED EDITS ===
        ENTRY: ## Existing Character
        FILE: characters
        CURRENT: - Role: unknown
        PROPOSED: - Role: idol trainee
        REASON: Revealed in this chapter.

        === STORY UPDATES ===
        TYPE: Main Plot
        UPDATE: Min-jun decided to audition.
      RESP

      result = described_class.parse(raw)

      expect(result).to be_success
      expect(result.new_entries.map(&:section_key)).to eq(%w[characters locations])
      expect(result.new_entries.first.heading).to eq("Kim Min-jun (김민준) — English")
      expect(result.proposed_edits.length).to eq(1)
      expect(result.proposed_edits.first.section_key).to eq("characters")
      expect(result.story_updates.length).to eq(1)
      expect(result.story_updates.first.type).to eq("Main Plot")
    end

    it "assigns stable per-type ids and a pending decision-free card_type wire hash" do
      raw = <<~RESP
        === NEW ENTRIES ===
        ### characters.md
        ## Entry A
        content a

        ## Entry B
        content b

        === PROPOSED EDITS ===
        NOTHING TO ADD

        === STORY UPDATES ===
        NOTHING TO ADD
      RESP

      result = described_class.parse(raw)
      ids = result.new_entries.map(&:id)
      expect(ids).to eq(%w[new_entry_0 new_entry_1])
      expect(result.new_entries.first.to_card_hash).to include(
        "id" => "new_entry_0", "card_type" => "new_entry", "decision" => "pending"
      )
    end

    it "treats NOTHING TO ADD sections as legitimately empty, not a failure" do
      raw = <<~RESP
        === NEW ENTRIES ===
        NOTHING TO ADD

        === PROPOSED EDITS ===
        NOTHING TO ADD

        === STORY UPDATES ===
        NOTHING TO ADD
      RESP

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.new_entries).to be_empty
      expect(result.proposed_edits).to be_empty
      expect(result.story_updates).to be_empty
    end

    it "fails closed when the response has none of the three section markers at all" do
      result = described_class.parse("The model just wrote some unstructured prose instead.")

      expect(result).not_to be_success
      expect(result.failure_reason).to eq(:missing_markers)
    end

    it "fails closed on a zero-byte response" do
      result = described_class.parse("")
      expect(result).not_to be_success
      expect(result.failure_reason).to eq(:missing_markers)
    end

    it "fails the whole call when the response exceeds the size cap, before any card is built" do
      huge = "=== NEW ENTRIES ===\n" + ("x" * (described_class::MAX_RESPONSE_BYTES + 1))
      result = described_class.parse(huge)

      expect(result).not_to be_success
      expect(result.failure_reason).to eq(:response_too_large)
    end

    it "fails the whole call when more than the max card count is produced" do
      entries = (described_class::MAX_CARDS + 1).times.map { |i| "## Entry #{i}\ncontent #{i}" }.join("\n\n")
      raw = "=== NEW ENTRIES ===\n### characters.md\n#{entries}\n\n=== PROPOSED EDITS ===\nNOTHING TO ADD\n\n=== STORY UPDATES ===\nNOTHING TO ADD\n"

      result = described_class.parse(raw)
      expect(result).not_to be_success
      expect(result.failure_reason).to eq(:too_many_cards)
    end

    it "fails the whole call when a field exceeds the max field length" do
      long_content = "## Entry\n" + ("a" * (described_class::MAX_FIELD_LENGTH + 1))
      raw = "=== NEW ENTRIES ===\n### characters.md\n#{long_content}\n\n=== PROPOSED EDITS ===\nNOTHING TO ADD\n\n=== STORY UPDATES ===\nNOTHING TO ADD\n"

      result = described_class.parse(raw)
      expect(result).not_to be_success
      expect(result.failure_reason).to eq(:field_too_long)
    end

    it "accepts a field exactly at the max length" do
      content = "## Entry\n" + ("a" * (described_class::MAX_FIELD_LENGTH - "## Entry\n".length))
      raw = "=== NEW ENTRIES ===\n### characters.md\n#{content}\n\n=== PROPOSED EDITS ===\nNOTHING TO ADD\n\n=== STORY UPDATES ===\nNOTHING TO ADD\n"

      result = described_class.parse(raw)
      expect(result).to be_success
    end

    it "rejects (not fatally) a new-entries label that doesn't resolve to a canonical section key" do
      raw = <<~RESP
        === NEW ENTRIES ===
        ### not_a_real_file.md
        ## Some Entry
        content

        === PROPOSED EDITS ===
        NOTHING TO ADD

        === STORY UPDATES ===
        NOTHING TO ADD
      RESP

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.new_entries).to be_empty
    end

    it "rejects a proposed edit block missing a required field, without failing the whole call" do
      raw = <<~RESP
        === NEW ENTRIES ===
        NOTHING TO ADD

        === PROPOSED EDITS ===
        ENTRY: ## Some Entry
        FILE: characters
        CURRENT: old text
        PROPOSED: new text

        === STORY UPDATES ===
        NOTHING TO ADD
      RESP

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.proposed_edits).to be_empty
    end

    it "rejects a proposed edit whose FILE doesn't resolve to a canonical section key" do
      raw = <<~RESP
        === NEW ENTRIES ===
        NOTHING TO ADD

        === PROPOSED EDITS ===
        ENTRY: ## Some Entry
        FILE: not_a_real_section
        CURRENT: old text
        PROPOSED: new text
        REASON: because

        === STORY UPDATES ===
        NOTHING TO ADD
      RESP

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.proposed_edits).to be_empty
    end

    it "allows duplicate CURRENT text across separate proposed edits (writer's job to catch ambiguity, not the parser's)" do
      raw = <<~RESP
        === NEW ENTRIES ===
        NOTHING TO ADD

        === PROPOSED EDITS ===
        ENTRY: ## Entry A
        FILE: characters
        CURRENT: - Role:
        PROPOSED: - Role: idol trainee
        REASON: reason a

        ENTRY: ## Entry B
        FILE: characters
        CURRENT: - Role:
        PROPOSED: - Role: rival
        REASON: reason b

        === STORY UPDATES ===
        NOTHING TO ADD
      RESP

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.proposed_edits.length).to eq(2)
    end

    it "rejects a story update block missing UPDATE" do
      raw = <<~RESP
        === NEW ENTRIES ===
        NOTHING TO ADD

        === PROPOSED EDITS ===
        NOTHING TO ADD

        === STORY UPDATES ===
        TYPE: Main Plot
      RESP

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.story_updates).to be_empty
    end

    it "normalises Windows (CRLF) line endings so headings don't capture trailing carriage returns" do
      raw = "=== NEW ENTRIES ===\r\n### characters.md\r\n## Windows Entry\r\n- Role: test\r\n\r\n" \
            "=== PROPOSED EDITS ===\r\nNOTHING TO ADD\r\n\r\n=== STORY UPDATES ===\r\nNOTHING TO ADD\r\n"

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.new_entries.first.heading).to eq("Windows Entry")
      expect(result.new_entries.first.content).not_to include("\r")
    end

    it "does not misparse markdown content with embedded ### sequences as a new file-label header" do
      raw = <<~RESP
        === NEW ENTRIES ===
        ### characters.md
        ## Entry With Nested Heading
        Some notes that mention ### not a real header, just prose.

        === PROPOSED EDITS ===
        NOTHING TO ADD

        === STORY UPDATES ===
        NOTHING TO ADD
      RESP

      result = described_class.parse(raw)
      expect(result).to be_success
      expect(result.new_entries.length).to eq(1)
      expect(result.new_entries.first.content).to include("not a real header")
    end

    it "rejects a response with invalid byte sequences for its encoding" do
      invalid = (+"=== NEW ENTRIES ===\n\xFF\xFE").force_encoding("UTF-8")
      result = described_class.parse(invalid)

      expect(result).not_to be_success
      expect(result.failure_reason).to eq(:invalid_encoding)
    end

    it "rerunning an identical response twice produces identical cards (parser is a pure function)" do
      raw = <<~RESP
        === NEW ENTRIES ===
        ### characters.md
        ## Entry A
        content a

        === PROPOSED EDITS ===
        NOTHING TO ADD

        === STORY UPDATES ===
        NOTHING TO ADD
      RESP

      first  = described_class.parse(raw)
      second = described_class.parse(raw)

      expect(first.new_entries.map(&:to_card_hash)).to eq(second.new_entries.map(&:to_card_hash))
    end
  end
end
