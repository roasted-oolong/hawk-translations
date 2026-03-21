require "rails_helper"

RSpec.describe BibleCulturalPhrase, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      phrase = build(:bible_cultural_phrase)
      expect(phrase).to be_valid
    end

    it "requires novel" do
      phrase = build(:bible_cultural_phrase, novel: nil)
      expect(phrase).not_to be_valid
      expect(phrase.errors[:novel]).to be_present
    end

    it "requires phrase" do
      phrase = build(:bible_cultural_phrase, phrase: nil)
      expect(phrase).not_to be_valid
      expect(phrase.errors[:phrase]).to be_present
    end

    it "allows all optional fields to be nil" do
      phrase = build(:bible_cultural_phrase,
        korean_phrase: nil, literal_translation: nil, intended_meaning: nil,
        context: nil, established_translation: nil,
        first_appearance_chapter: nil, notes: nil)
      expect(phrase).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a novel" do
      novel = create(:novel)
      phrase = create(:bible_cultural_phrase, novel: novel)
      expect(phrase.novel).to eq(novel)
    end
  end

  describe "callbacks" do
    it "sets last_updated_at on create" do
      phrase = create(:bible_cultural_phrase)
      expect(phrase.last_updated_at).to be_present
    end

    it "updates last_updated_at on update" do
      phrase = create(:bible_cultural_phrase)
      original = phrase.last_updated_at
      travel_to(1.minute.from_now) do
        phrase.update!(phrase: "Updated Phrase")
      end
      expect(phrase.last_updated_at).to be > original
    end
  end

  describe "scopes" do
    it "orders by phrase ascending with .by_phrase" do
      novel  = create(:novel)
      zeal   = create(:bible_cultural_phrase, novel: novel, phrase: "Zeal phrase")
      ambit  = create(:bible_cultural_phrase, novel: novel, phrase: "Ambit phrase")
      expect(novel.bible_cultural_phrases.by_phrase).to eq([ ambit, zeal ])
    end
  end

  describe "novel destroy cascade" do
    it "is destroyed when its novel is destroyed" do
      novel = create(:novel)
      create(:bible_cultural_phrase, novel: novel)
      expect { novel.destroy }.to change(BibleCulturalPhrase, :count).by(-1)
    end
  end

  describe "#embeddable_text" do
    it "returns a non-blank string" do
      phrase = build(:bible_cultural_phrase, phrase: "Fighting")
      expect(phrase.embeddable_text).to be_a(String)
      expect(phrase.embeddable_text).not_to be_blank
    end

    it "includes the phrase" do
      phrase = build(:bible_cultural_phrase, phrase: "Fighting")
      expect(phrase.embeddable_text).to include("Fighting")
    end

    it "includes korean_phrase when present" do
      phrase = build(:bible_cultural_phrase, phrase: "Fighting", korean_phrase: "파이팅")
      expect(phrase.embeddable_text).to include("파이팅")
    end

    it "includes intended_meaning when present" do
      phrase = build(:bible_cultural_phrase, phrase: "Fighting", intended_meaning: "Good luck / You can do it")
      expect(phrase.embeddable_text).to include("Good luck / You can do it")
    end

    it "does not raise when all optional fields are nil" do
      phrase = build(:bible_cultural_phrase,
        korean_phrase: nil, literal_translation: nil, intended_meaning: nil,
        context: nil, established_translation: nil, notes: nil)
      expect { phrase.embeddable_text }.not_to raise_error
    end
  end
end
