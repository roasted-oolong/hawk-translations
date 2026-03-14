require "rails_helper"

RSpec.describe BibleCharacter, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      character = build(:bible_character)
      expect(character).to be_valid
    end

    it "requires novel" do
      character = build(:bible_character, novel: nil)
      expect(character).not_to be_valid
      expect(character.errors[:novel]).to be_present
    end

    it "requires name" do
      character = build(:bible_character, name: nil)
      expect(character).not_to be_valid
      expect(character.errors[:name]).to be_present
    end

    it "allows all optional fields to be nil" do
      character = build(:bible_character,
        korean_name: nil, aliases: nil, role: nil, significance: nil,
        physical_description: nil, speech_pattern: nil,
        honorifics_used_toward: nil, honorifics_they_use: nil,
        relationships: nil, first_appearance_chapter: nil, notes: nil)
      expect(character).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a novel" do
      novel = create(:novel)
      character = create(:bible_character, novel: novel)
      expect(character.novel).to eq(novel)
    end
  end

  describe "callbacks" do
    it "sets last_updated_at on create" do
      character = create(:bible_character)
      expect(character.last_updated_at).to be_present
    end

    it "updates last_updated_at on update" do
      character = create(:bible_character)
      original = character.last_updated_at
      travel_to(1.minute.from_now) do
        character.update!(name: "New Name")
      end
      expect(character.last_updated_at).to be > original
    end
  end

  describe "scopes" do
    it "orders by name ascending with .by_name" do
      novel = create(:novel)
      zara  = create(:bible_character, novel: novel, name: "Zara")
      anya  = create(:bible_character, novel: novel, name: "Anya")
      expect(novel.bible_characters.by_name).to eq([ anya, zara ])
    end
  end

  describe "novel destroy cascade" do
    it "is destroyed when its novel is destroyed" do
      novel = create(:novel)
      create(:bible_character, novel: novel)
      expect { novel.destroy }.to change(BibleCharacter, :count).by(-1)
    end
  end
end
