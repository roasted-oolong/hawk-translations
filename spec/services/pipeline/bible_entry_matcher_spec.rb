require "rails_helper"

RSpec.describe Pipeline::BibleEntryMatcher do
  let(:novel) { create(:novel) }
  let(:matcher) { described_class.new(novel) }

  describe "#parse" do
    it "splits multiple '## ' headings into separate entries" do
      content = <<~MD
        ## Park Jisoo (박지수)
        - Korean name: 박지수
        - Role: Protagonist

        ## Kim Minjun (김민준)
        - Korean name: 김민준
        - Role: Antagonist
      MD

      entries = matcher.parse(:characters, content)

      expect(entries.map { |e| e[:name] }).to contain_exactly("Park Jisoo", "Kim Minjun")
    end

    it "derives korean_key from the parenthesized Korean name when Korean name field is absent" do
      content = <<~MD
        ## Test Location (테스트 장소)
        - Significance: Where things happen.
      MD

      entry = matcher.parse(:locations, content).first
      expect(entry[:korean_key]).to eq(Pipeline::BibleUtils.normalize_korean("테스트 장소"))
    end

    it "does not classify — every parsed entry has no is_existing key" do
      content = "## Someone (누군가)\n- Role: Extra\n"
      entry = matcher.parse(:characters, content).first
      expect(entry).not_to have_key(:is_existing)
    end

    it "parses story entries by title and content, skipping '---' separator lines" do
      content = <<~MD
        ## Main Plot Thread
        ---
        Sung-ah confronts her manager.
      MD

      entry = matcher.parse(:story, content).first
      expect(entry[:title]).to eq("Main Plot Thread")
      expect(entry[:content]).to eq("Sung-ah confronts her manager.")
      expect(entry[:category]).to eq("main_plot")
    end
  end

  describe "#classify" do
    it "tags a brand-new entry as is_existing: false" do
      content = "## New Character (신규)\n- Role: Extra\n"
      entry = matcher.classify(:characters, content).first
      expect(entry[:is_existing]).to be false
    end

    it "tags a changed entry as is_existing: true with field_changes" do
      create(:bible_character, novel: novel, name: "Sung-ah", korean_name: "성아", role: "Old role")
      content = "## Sung-ah (성아)\n- Korean name: 성아\n- Role: New role\n"

      entry = matcher.classify(:characters, content).first

      expect(entry[:is_existing]).to be true
      expect(entry[:field_changes]).to have_key(:role)
      expect(entry[:field_changes][:role]).to eq({ was: "Old role", now: "New role" })
    end

    it "drops an entry that matches an existing record with no actual differences" do
      create(:bible_character, novel: novel, name: "Sung-ah", korean_name: "성아", role: "Lead")
      content = "## Sung-ah (성아)\n- Korean name: 성아\n- Role: Lead\n"

      expect(matcher.classify(:characters, content)).to be_empty
    end

    it "drops an entry whose korean_key is dismissed" do
      novel.update_column(:preread_dismissed_keys, '["characters:성아"]')
      content = "## Sung-ah (성아)\n- Korean name: 성아\n- Role: Lead\n"

      expect(matcher.classify(:characters, content)).to be_empty
    end

    it "matches cultural phrases by korean_phrase only, never by an English field" do
      create(:bible_cultural_phrase, novel: novel, korean_phrase: "눈치 없다", context: "old context")
      content = <<~MD
        ## 눈치 없다
        - Context: new context
      MD

      entry = matcher.classify(:cultural_phrases, content).first
      expect(entry[:is_existing]).to be true
      expect(entry[:field_changes]).to have_key(:context)
    end
  end

  describe "#classify_parsed" do
    it "classifies pre-parsed entries without re-parsing (equivalent to #classify)" do
      content = "## New Character (신규)\n- Role: Extra\n"
      parsed = matcher.parse(:characters, content)

      expect(matcher.classify_parsed(:characters, parsed)).to eq(matcher.classify(:characters, content))
    end
  end

  describe "#matching_record" do
    it "returns the matching live record by korean_key" do
      character = create(:bible_character, novel: novel, name: "Sung-ah", korean_name: "성아")
      entry = matcher.parse(:characters, "## Sung-ah (성아)\n- Korean name: 성아\n").first

      expect(matcher.matching_record(:characters, entry)).to eq(character)
    end

    it "returns nil when nothing matches" do
      entry = matcher.parse(:characters, "## Nobody (없음)\n- Korean name: 없음\n").first
      expect(matcher.matching_record(:characters, entry)).to be_nil
    end
  end
end
