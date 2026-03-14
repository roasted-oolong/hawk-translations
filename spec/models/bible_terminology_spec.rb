require "rails_helper"

RSpec.describe BibleTerminology, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      term = build(:bible_terminology)
      expect(term).to be_valid
    end

    it "requires novel" do
      term = build(:bible_terminology, novel: nil)
      expect(term).not_to be_valid
      expect(term.errors[:novel]).to be_present
    end

    it "requires term" do
      term = build(:bible_terminology, term: nil)
      expect(term).not_to be_valid
      expect(term.errors[:term]).to be_present
    end

    it "allows all optional fields to be nil" do
      term = build(:bible_terminology,
        korean_term: nil, definition: nil, usage_notes: nil,
        first_appearance_chapter: nil, notes: nil)
      expect(term).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a novel" do
      novel = create(:novel)
      term = create(:bible_terminology, novel: novel)
      expect(term.novel).to eq(novel)
    end
  end

  describe "callbacks" do
    it "sets last_updated_at on create" do
      term = create(:bible_terminology)
      expect(term.last_updated_at).to be_present
    end

    it "updates last_updated_at on update" do
      term = create(:bible_terminology)
      original = term.last_updated_at
      travel_to(1.minute.from_now) do
        term.update!(term: "Updated Term")
      end
      expect(term.last_updated_at).to be > original
    end
  end

  describe "scopes" do
    it "orders by term ascending with .by_term" do
      novel = create(:novel)
      zen   = create(:bible_terminology, novel: novel, term: "Zen")
      aura  = create(:bible_terminology, novel: novel, term: "Aura")
      expect(novel.bible_terminologies.by_term).to eq([ aura, zen ])
    end
  end

  describe "novel destroy cascade" do
    it "is destroyed when its novel is destroyed" do
      novel = create(:novel)
      create(:bible_terminology, novel: novel)
      expect { novel.destroy }.to change(BibleTerminology, :count).by(-1)
    end
  end
end
