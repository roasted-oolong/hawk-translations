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
