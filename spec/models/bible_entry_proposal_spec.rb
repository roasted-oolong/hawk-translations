require "rails_helper"

RSpec.describe BibleEntryProposal, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      expect(build(:bible_entry_proposal)).to be_valid
    end

    it "requires korean_key" do
      proposal = build(:bible_entry_proposal, korean_key: nil)
      expect(proposal).not_to be_valid
      expect(proposal.errors[:korean_key]).to be_present
    end

    it "requires entry_type" do
      proposal = build(:bible_entry_proposal, entry_type: nil)
      expect(proposal).not_to be_valid
      expect(proposal.errors[:entry_type]).to be_present
    end

    it "rejects a duplicate novel_id/entry_type/korean_key combination" do
      novel = create(:novel)
      chapter = create(:chapter, novel: novel)
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character", korean_key: "same-key")
      dup = build(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character", korean_key: "same-key")
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "enum entry_type" do
    it "accepts all five bible categories" do
      %w[character location terminology cultural_phrase story].each do |type|
        proposal = build(:bible_entry_proposal, entry_type: type)
        expect(proposal).to be_valid
      end
    end
  end

  describe "novel/chapter destroy cascade" do
    # Novel#destroy cascades to its chapters, whose before_destroy hook
    # deletes on-disk source files and requires HAWK_PROJECT_ROOT — mirrors
    # chapter_spec.rb's "on destroy" setup, unrelated to this model itself.
    around do |example|
      novel_dir = Dir.mktmpdir
      orig_root = ENV["HAWK_PROJECT_ROOT"]
      ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)
      @novel_dir = novel_dir
      example.run
      ENV["HAWK_PROJECT_ROOT"] = orig_root
      FileUtils.rm_rf(novel_dir)
    end

    it "is destroyed when its novel is destroyed" do
      novel = create(:novel, directory_name: File.basename(@novel_dir))
      proposal = create(:bible_entry_proposal, novel: novel)
      expect { novel.destroy }.to change(BibleEntryProposal, :count).by(-1)
    end
  end

  describe "#approve!" do
    it "creates a new bible_character record when existing_record_id is nil" do
      novel = create(:novel)
      chapter = create(:chapter, novel: novel)
      proposal = create(:bible_entry_proposal, novel: novel, chapter: chapter,
                         entry_type: "character", existing_record_id: nil,
                         fields: { "name" => "Sung-ah", "role" => "Lead" })

      expect { proposal.approve! }.to change(BibleCharacter, :count).by(1)

      character = novel.bible_characters.last
      expect(character.name).to eq("Sung-ah")
      expect(character.role).to eq("Lead")
    end

    it "updates the existing record when existing_record_id is set" do
      novel = create(:novel)
      chapter = create(:chapter, novel: novel)
      character = create(:bible_character, novel: novel, name: "Old Name")
      proposal = create(:bible_entry_proposal, novel: novel, chapter: chapter,
                         entry_type: "character", existing_record_id: character.id,
                         fields: { "name" => "New Name" })

      expect { proposal.approve! }.not_to change(BibleCharacter, :count)
      expect(character.reload.name).to eq("New Name")
    end

    it "falls back to creating a fresh record when existing_record_id points at a deleted row" do
      novel = create(:novel)
      chapter = create(:chapter, novel: novel)
      character = create(:bible_character, novel: novel)
      dangling_id = character.id
      character.destroy!

      proposal = create(:bible_entry_proposal, novel: novel, chapter: chapter,
                         entry_type: "character", existing_record_id: dangling_id,
                         fields: { "name" => "Resurrected" })

      expect { proposal.approve! }.to change(BibleCharacter, :count).by(1)
      expect(novel.bible_characters.last.name).to eq("Resurrected")
    end

    it "deletes the proposal after approving" do
      proposal = create(:bible_entry_proposal, fields: { "name" => "Someone" })
      expect { proposal.approve! }.to change(BibleEntryProposal, :count).by(-1)
    end

    it "resolves each entry_type to its own bible table" do
      novel = create(:novel)
      chapter = create(:chapter, novel: novel)

      proposal = create(:bible_entry_proposal, novel: novel, chapter: chapter,
                         entry_type: "location", existing_record_id: nil,
                         fields: { "name" => "HS Entertainment" })

      expect { proposal.approve! }.to change(BibleLocation, :count).by(1)
    end
  end

  describe "#skip!" do
    it "deletes the proposal" do
      proposal = create(:bible_entry_proposal)
      expect { proposal.skip! }.to change(BibleEntryProposal, :count).by(-1)
    end

    it "appends the legacy-section:korean_key form onto the novel's preread_dismissed_keys" do
      novel = create(:novel)
      proposal = create(:bible_entry_proposal, novel: novel, entry_type: "character", korean_key: "sung-ah")

      proposal.skip!

      # "characters" (plural), not entry_type's own "character" — see
      # BibleEntryProposal::ENTRY_TYPE_TO_LEGACY_SECTION.
      expect(JSON.parse(novel.reload.preread_dismissed_keys)).to include("characters:sung-ah")
    end

    it "does not create any live bible record" do
      proposal = create(:bible_entry_proposal)
      expect { proposal.skip! }.not_to change(BibleCharacter, :count)
    end
  end
end
