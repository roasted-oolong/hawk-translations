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

    it "requires korean_phrase" do
      phrase = build(:bible_cultural_phrase, korean_phrase: nil)
      expect(phrase).not_to be_valid
      expect(phrase.errors[:korean_phrase]).to be_present
    end

    it "allows all other fields to be nil" do
      phrase = build(:bible_cultural_phrase,
        literal_translation: nil, intended_meaning: nil,
        context: nil, first_appearance_chapter: nil, notes: nil)
      expect(phrase).to be_valid
    end

    describe "korean_phrase uniqueness per novel" do
      it "rejects an exact duplicate within the same novel" do
        novel = create(:novel)
        create(:bible_cultural_phrase, novel: novel, korean_phrase: "눈치 없다")
        dup = build(:bible_cultural_phrase, novel: novel, korean_phrase: "눈치 없다")

        expect(dup).not_to be_valid
        expect(dup.errors[:korean_phrase]).to be_present
      end

      it "rejects a near-duplicate that only differs by formatting drift" do
        novel = create(:novel)
        create(:bible_cultural_phrase, novel: novel, korean_phrase: "ＳＮＳ 감성")
        dup = build(:bible_cultural_phrase, novel: novel, korean_phrase: "sns 감성")

        expect(dup).not_to be_valid
        expect(dup.errors[:korean_phrase]).to be_present
      end

      it "allows the same korean_phrase in a different novel" do
        create(:bible_cultural_phrase, korean_phrase: "눈치 없다")
        other_novel_dup = build(:bible_cultural_phrase, korean_phrase: "눈치 없다")

        expect(other_novel_dup).to be_valid
      end

      it "does not flag a record against itself on update" do
        phrase = create(:bible_cultural_phrase, korean_phrase: "눈치 없다")
        phrase.notes = "updated"

        expect(phrase).to be_valid
      end
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
        phrase.update!(notes: "Updated notes")
      end
      expect(phrase.last_updated_at).to be > original
    end
  end

  describe "scopes" do
    it "orders by korean_phrase ascending with .by_korean_phrase" do
      novel  = create(:novel)
      zeal   = create(:bible_cultural_phrase, novel: novel, korean_phrase: "하 열정")
      ambit  = create(:bible_cultural_phrase, novel: novel, korean_phrase: "가 야망")
      expect(novel.bible_cultural_phrases.by_korean_phrase).to eq([ ambit, zeal ])
    end
  end

  describe "novel destroy cascade" do
    it "is destroyed when its novel is destroyed" do
      novel = create(:novel)
      create(:bible_cultural_phrase, novel: novel)
      expect { novel.destroy }.to change(BibleCulturalPhrase, :count).by(-1)
    end
  end

  describe "#translation_examples_text / #translation_examples_text=" do
    it "round-trips context:translation lines into the jsonb array" do
      phrase = build(:bible_cultural_phrase)
      phrase.translation_examples_text = "sarcastic tone: yeah, no big deal\nsincere tone: it's really nothing"

      expect(phrase.translation_examples).to eq([
        { "context" => "sarcastic tone", "translation" => "yeah, no big deal" },
        { "context" => "sincere tone", "translation" => "it's really nothing" }
      ])
      expect(phrase.translation_examples_text).to eq(
        "sarcastic tone: yeah, no big deal\nsincere tone: it's really nothing"
      )
    end

    it "accepts a line with no context prefix" do
      phrase = build(:bible_cultural_phrase)
      phrase.translation_examples_text = "no big deal"

      expect(phrase.translation_examples).to eq([ { "context" => nil, "translation" => "no big deal" } ])
    end

    it "ignores blank lines" do
      phrase = build(:bible_cultural_phrase)
      phrase.translation_examples_text = "a: b\n\n  \nc: d"

      expect(phrase.translation_examples.size).to eq(2)
    end

    it "returns an empty string when there are no examples" do
      phrase = build(:bible_cultural_phrase, translation_examples: [])
      expect(phrase.translation_examples_text).to eq("")
    end
  end

  describe "#embeddable_text" do
    it "returns a non-blank string" do
      phrase = build(:bible_cultural_phrase, korean_phrase: "파이팅")
      expect(phrase.embeddable_text).to be_a(String)
      expect(phrase.embeddable_text).not_to be_blank
    end

    it "includes korean_phrase" do
      phrase = build(:bible_cultural_phrase, korean_phrase: "파이팅")
      expect(phrase.embeddable_text).to include("파이팅")
    end

    it "includes intended_meaning when present" do
      phrase = build(:bible_cultural_phrase, korean_phrase: "파이팅", intended_meaning: "Good luck / You can do it")
      expect(phrase.embeddable_text).to include("Good luck / You can do it")
    end

    it "includes translation_examples text when present" do
      phrase = build(:bible_cultural_phrase, korean_phrase: "파이팅")
      phrase.translation_examples_text = "cheering: Fighting!"
      expect(phrase.embeddable_text).to include("Fighting!")
    end

    it "does not raise when all optional fields are nil" do
      phrase = build(:bible_cultural_phrase,
        literal_translation: nil, intended_meaning: nil,
        context: nil, notes: nil)
      expect { phrase.embeddable_text }.not_to raise_error
    end
  end
end
