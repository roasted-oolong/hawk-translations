require "rails_helper"

RSpec.describe BibleMarkdownParser do
  let(:novel) { create(:novel) }

  describe "#pending_entries" do
    context "when the bible directory does not exist" do
      before { allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return("") }

      it "returns empty collections for all categories" do
        result = described_class.new(novel).pending_entries
        expect(result.values.all?(&:empty?)).to be true
      end
    end

    context "with dismissed keys stored on the novel" do
      let(:bible_dir) { Dir.mktmpdir }

      before do
        FileUtils.mkdir_p(File.join(bible_dir, "bible"))
        allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return(File.dirname(bible_dir))
        allow(novel).to receive(:directory_name).and_return(File.basename(bible_dir))

        File.write(File.join(bible_dir, "bible", "characters.md"), <<~MD)
          ## Park Jisoo (박지수)
          - Korean name: 박지수
          - Role: Protagonist

          ## Kim Minjun (김민준)
          - Korean name: 김민준
          - Role: Antagonist
        MD

        %w[locations.md terminology.md cultural_phrases.md story.md].each do |f|
          FileUtils.touch(File.join(bible_dir, "bible", f))
        end
      end

      after { FileUtils.rm_rf(bible_dir) }

      it "includes all characters when none are dismissed" do
        result = described_class.new(novel).pending_entries
        names = result[:characters].map { |e| e[:name] }
        expect(names).to include("Park Jisoo", "Kim Minjun")
      end

      it "excludes characters whose composite key is in preread_dismissed_keys" do
        novel.update_column(:preread_dismissed_keys, '["characters:김민준"]')
        result = described_class.new(novel).pending_entries
        names = result[:characters].map { |e| e[:name] }
        expect(names).to include("Park Jisoo")
        expect(names).not_to include("Kim Minjun")
      end
    end

    context "when the dismissed key and the re-parsed entry differ only by formatting drift" do
      let(:bible_dir) { Dir.mktmpdir }

      before do
        FileUtils.mkdir_p(File.join(bible_dir, "bible"))
        allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return(File.dirname(bible_dir))
        allow(novel).to receive(:directory_name).and_return(File.basename(bible_dir))

        # Full-width Latin script — a realistic form for a Korean-loanword term
        # (e.g. "ＳＮＳ" for social media) — versus the half-width dismissed key.
        File.write(File.join(bible_dir, "bible", "terminology.md"), <<~MD)
          ## SNS Culture (ＳＮＳ)
          - Korean term: ＳＮＳ
          - Definition: social media presence expected of idols
        MD

        %w[characters.md locations.md cultural_phrases.md story.md].each do |f|
          FileUtils.touch(File.join(bible_dir, "bible", f))
        end
      end

      after { FileUtils.rm_rf(bible_dir) }

      it "still excludes a previously-dismissed term reparsed with a different Unicode width/case" do
        novel.update_column(:preread_dismissed_keys, '["terminology:sns"]')
        result = described_class.new(novel).pending_entries
        expect(result[:terminology]).to be_empty
      end
    end

    context "cultural phrases — Korean-only heading, no English fallback" do
      let(:bible_dir) { Dir.mktmpdir }

      before do
        FileUtils.mkdir_p(File.join(bible_dir, "bible"))
        allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return(File.dirname(bible_dir))
        allow(novel).to receive(:directory_name).and_return(File.basename(bible_dir))

        File.write(File.join(bible_dir, "bible", "cultural_phrases.md"), <<~MD)
          ## 눈치 없다
          - Literal translation: Doesn't have "nunchi" (social awareness)
          - Intended meaning: Oblivious to the room's mood
          - Context: Used when a character misses an obvious social cue.
          - Notes: Renders differently depending on scene tone.
        MD

        %w[characters.md locations.md terminology.md story.md].each do |f|
          FileUtils.touch(File.join(bible_dir, "bible", f))
        end
      end

      after { FileUtils.rm_rf(bible_dir) }

      it "parses the heading itself as korean_phrase, with no phrase/established_translation keys" do
        entry = described_class.new(novel).pending_entries[:cultural_phrases].first
        expect(entry[:korean_phrase]).to eq("눈치 없다")
        expect(entry).not_to have_key(:phrase)
        expect(entry).not_to have_key(:established_translation)
      end

      it "matches an existing record by korean_phrase alone, never by an English field" do
        create(:bible_cultural_phrase, novel: novel, korean_phrase: "눈치 없다", context: "old context")

        # BibleDocSynced (docs/PREREAD_STAGING_DESIGN.md, Part 3) just
        # regenerated cultural_phrases.md from the record above as part of
        # creating it, so it no longer differs from the DB. Re-write the
        # file's original (pre-record) content to restore the stale-file
        # premise this test exercises — it's BibleMarkdownParser's own
        # diffing this test is after, independent of doc-sync.
        File.write(File.join(bible_dir, "bible", "cultural_phrases.md"), <<~MD)
          ## 눈치 없다
          - Literal translation: Doesn't have "nunchi" (social awareness)
          - Intended meaning: Oblivious to the room's mood
          - Context: Used when a character misses an obvious social cue.
          - Notes: Renders differently depending on scene tone.
        MD

        entry = described_class.new(novel).pending_entries[:cultural_phrases].first
        expect(entry[:is_existing]).to be true
        expect(entry[:field_changes]).to have_key(:context)
      end

      it "reports no pending change once the DB record matches the reparsed entry exactly" do
        create(:bible_cultural_phrase, novel: novel, korean_phrase: "눈치 없다",
               literal_translation: "Doesn't have \"nunchi\" (social awareness)",
               intended_meaning: "Oblivious to the room's mood",
               context: "Used when a character misses an obvious social cue.",
               notes: "Renders differently depending on scene tone.")

        result = described_class.new(novel).pending_entries[:cultural_phrases]
        expect(result).to be_empty
      end
    end
  end

  describe "#pending_breakdown" do
    context "when the bible directory does not exist" do
      before { allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return("") }

      it "returns a zero total and empty per-category counts" do
        result = described_class.new(novel).pending_breakdown
        expect(result[:total]).to eq(0)
        expect(result[:by_category].values.all?(&:zero?)).to be true
      end
    end

    context "with pending characters" do
      let(:bible_dir) { Dir.mktmpdir }

      before do
        FileUtils.mkdir_p(File.join(bible_dir, "bible"))
        allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return(File.dirname(bible_dir))
        allow(novel).to receive(:directory_name).and_return(File.basename(bible_dir))

        File.write(File.join(bible_dir, "bible", "characters.md"), <<~MD)
          ## Park Jisoo (박지수)
          - Korean name: 박지수
          - Role: Protagonist
        MD

        %w[locations.md terminology.md cultural_phrases.md story.md].each do |f|
          FileUtils.touch(File.join(bible_dir, "bible", f))
        end
      end

      after { FileUtils.rm_rf(bible_dir) }

      it "sums per-category counts into a total matching #pending_entries" do
        result = described_class.new(novel).pending_breakdown
        expect(result[:by_category][:characters]).to eq(1)
        expect(result[:total]).to eq(1)
      end
    end
  end

  describe "#dismissed_entries" do
    let(:bible_dir) { Dir.mktmpdir }

    before do
      FileUtils.mkdir_p(File.join(bible_dir, "bible"))
      allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return(File.dirname(bible_dir))
      allow(novel).to receive(:directory_name).and_return(File.basename(bible_dir))

      File.write(File.join(bible_dir, "bible", "characters.md"), <<~MD)
        ## Park Jisoo (박지수)
        - Korean name: 박지수
        - Role: Protagonist

        ## Kim Minjun (김민준)
        - Korean name: 김민준
        - Role: Antagonist
      MD

      %w[locations.md terminology.md cultural_phrases.md story.md].each do |f|
        FileUtils.touch(File.join(bible_dir, "bible", f))
      end
    end

    after { FileUtils.rm_rf(bible_dir) }

    context "when no keys are dismissed" do
      it "returns empty collections for all categories" do
        result = described_class.new(novel).dismissed_entries
        expect(result.values.all?(&:empty?)).to be true
      end
    end

    context "when a character key is dismissed" do
      before { novel.update_column(:preread_dismissed_keys, '["characters:김민준"]') }

      it "returns only the dismissed character" do
        result = described_class.new(novel).dismissed_entries
        names = result[:characters].map { |e| e[:name] }
        expect(names).to eq(["Kim Minjun"])
      end

      it "does not include the non-dismissed character" do
        result = described_class.new(novel).dismissed_entries
        names = result[:characters].map { |e| e[:name] }
        expect(names).not_to include("Park Jisoo")
      end
    end

    context "when the bible directory does not exist" do
      before { allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return("") }

      it "returns empty collections" do
        result = described_class.new(novel).dismissed_entries
        expect(result.values.all?(&:empty?)).to be true
      end
    end
  end
end
