require "rails_helper"

RSpec.describe Pipeline::BibleEntryProposalBackfill do
  let(:novel) { create(:novel) }

  def write_bible_files(novel, characters: nil)
    bible_dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(bible_dir, "bible"))
    allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return(File.dirname(bible_dir))
    allow(novel).to receive(:directory_name).and_return(File.basename(bible_dir))

    File.write(File.join(bible_dir, "bible", "characters.md"), characters) if characters
    %w[characters.md locations.md terminology.md cultural_phrases.md story.md].each do |f|
      path = File.join(bible_dir, "bible", f)
      FileUtils.touch(path) unless File.exist?(path)
    end

    bible_dir
  end

  after { FileUtils.rm_rf(@bible_dir) if @bible_dir }

  describe "#call" do
    it "creates a proposal for a brand-new pending entry, attributed to its parsed chapter" do
      create(:chapter, novel: novel, number: 5)
      create(:chapter, novel: novel, number: 6)
      @bible_dir = write_bible_files(novel, characters: <<~MD)
        ## Yoo Areum (유아름)
        - Korean name: 유아름
        - Role: Sidekick
        - First appearance: 5
      MD

      result = described_class.new(novel).call

      expect(result.created).to eq(1)
      expect(result.updated).to eq(0)
      expect(result.skipped).to eq(0)

      proposal = BibleEntryProposal.find_by!(novel: novel, entry_type: "character")
      expect(proposal.fields["name"]).to eq("Yoo Areum")
      expect(proposal.chapter.number).to eq(5)
    end

    it "falls back to the novel's most recent chapter when the entry has no attributable chapter" do
      create(:chapter, novel: novel, number: 3)
      create(:chapter, novel: novel, number: 9)
      @bible_dir = write_bible_files(novel, characters: <<~MD)
        ## No Chapter Field (없음)
        - Korean name: 없음
        - Role: Extra
      MD

      described_class.new(novel).call

      expect(BibleEntryProposal.last.chapter.number).to eq(9)
    end

    it "skips (does not raise) an entry when the novel has no chapters at all to attribute to" do
      @bible_dir = write_bible_files(novel, characters: <<~MD)
        ## No Chapters Yet (없음)
        - Korean name: 없음
        - Role: Extra
      MD

      result = described_class.new(novel).call

      expect(result.created).to eq(0)
      expect(result.skipped).to eq(1)
      expect(BibleEntryProposal.count).to eq(0)
    end

    it "is idempotent — re-running updates the existing proposal instead of duplicating it" do
      create(:chapter, novel: novel, number: 5)
      @bible_dir = write_bible_files(novel, characters: <<~MD)
        ## Yoo Areum (유아름)
        - Korean name: 유아름
        - Role: Sidekick
        - First appearance: 5
      MD

      backfill = described_class.new(novel)
      backfill.call
      result = backfill.call

      expect(result.created).to eq(0)
      expect(result.updated).to eq(1)
      expect(BibleEntryProposal.count).to eq(1)
    end

    it "does not backfill an entry whose korean_key is already dismissed" do
      create(:chapter, novel: novel, number: 5)
      novel.update_column(:preread_dismissed_keys, '["characters:유아름"]')
      @bible_dir = write_bible_files(novel, characters: <<~MD)
        ## Yoo Areum (유아름)
        - Korean name: 유아름
        - Role: Sidekick
      MD

      result = described_class.new(novel).call

      expect(result.created).to eq(0)
      expect(BibleEntryProposal.count).to eq(0)
    end

    it "does not backfill an entry that matches an existing record with no actual differences" do
      create(:chapter, novel: novel, number: 5)
      create(:bible_character, novel: novel, name: "Yoo Areum", korean_name: "유아름", role: "Sidekick")
      @bible_dir = write_bible_files(novel, characters: <<~MD)
        ## Yoo Areum (유아름)
        - Korean name: 유아름
        - Role: Sidekick
      MD

      result = described_class.new(novel).call

      expect(result.created).to eq(0)
      expect(BibleEntryProposal.count).to eq(0)
    end

    it "does not touch or approve/skip anything — only stages proposal rows" do
      create(:chapter, novel: novel, number: 5)
      @bible_dir = write_bible_files(novel, characters: <<~MD)
        ## Yoo Areum (유아름)
        - Korean name: 유아름
      MD

      described_class.new(novel).call

      expect(BibleCharacter.count).to eq(0)
      expect(JSON.parse(novel.reload.preread_dismissed_keys)).to eq([])
    end
  end
end
