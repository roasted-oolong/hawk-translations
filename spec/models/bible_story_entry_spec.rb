require "rails_helper"

RSpec.describe BibleStoryEntry, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      entry = build(:bible_story_entry)
      expect(entry).to be_valid
    end

    it "requires novel" do
      entry = build(:bible_story_entry, novel: nil)
      expect(entry).not_to be_valid
      expect(entry.errors[:novel]).to be_present
    end

    it "requires title" do
      entry = build(:bible_story_entry, title: nil)
      expect(entry).not_to be_valid
      expect(entry.errors[:title]).to be_present
    end

    it "requires category" do
      entry = build(:bible_story_entry, category: nil)
      expect(entry).not_to be_valid
      expect(entry.errors[:category]).to be_present
    end

    it "rejects an invalid category value" do
      expect {
        build(:bible_story_entry, category: "spoiler")
      }.to raise_error(ArgumentError)
    end

    it "allows all optional fields to be nil" do
      entry = build(:bible_story_entry,
        content: nil, first_appearance_chapter: nil, notes: nil)
      expect(entry).to be_valid
    end
  end

  describe "enums" do
    %w[main_plot subplot watch_list theme].each do |cat|
      it "accepts category: #{cat}" do
        entry = build(:bible_story_entry, category: cat)
        expect(entry).to be_valid
      end
    end
  end

  describe "associations" do
    it "belongs to a novel" do
      novel = create(:novel)
      entry = create(:bible_story_entry, novel: novel)
      expect(entry.novel).to eq(novel)
    end
  end

  describe "callbacks" do
    it "sets last_updated_at on create" do
      entry = create(:bible_story_entry)
      expect(entry.last_updated_at).to be_present
    end

    it "updates last_updated_at on update" do
      entry = create(:bible_story_entry)
      original = entry.last_updated_at
      travel_to(1.minute.from_now) do
        entry.update!(title: "Revised Title")
      end
      expect(entry.last_updated_at).to be > original
    end
  end

  describe "scopes" do
    it "orders by title ascending with .by_title" do
      novel  = create(:novel)
      zoom   = create(:bible_story_entry, novel: novel, title: "Zoom arc")
      alpha  = create(:bible_story_entry, novel: novel, title: "Alpha arc")
      expect(novel.bible_story_entries.by_title).to eq([ alpha, zoom ])
    end

    it "filters by category with .by_category" do
      novel    = create(:novel)
      plot     = create(:bible_story_entry, novel: novel, category: "main_plot")
      _subplot = create(:bible_story_entry, novel: novel, category: "subplot")
      expect(novel.bible_story_entries.by_category("main_plot")).to eq([ plot ])
    end
  end

  describe "novel destroy cascade" do
    it "is destroyed when its novel is destroyed" do
      novel = create(:novel)
      create(:bible_story_entry, novel: novel)
      expect { novel.destroy }.to change(BibleStoryEntry, :count).by(-1)
    end
  end
end
