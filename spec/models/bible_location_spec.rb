require "rails_helper"

RSpec.describe BibleLocation, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      location = build(:bible_location)
      expect(location).to be_valid
    end

    it "requires novel" do
      location = build(:bible_location, novel: nil)
      expect(location).not_to be_valid
      expect(location.errors[:novel]).to be_present
    end

    it "requires name" do
      location = build(:bible_location, name: nil)
      expect(location).not_to be_valid
      expect(location.errors[:name]).to be_present
    end

    it "allows all optional fields to be nil" do
      location = build(:bible_location,
        korean_name: nil, location_type: nil, description: nil,
        significance: nil, first_appearance_chapter: nil, notes: nil)
      expect(location).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a novel" do
      novel = create(:novel)
      location = create(:bible_location, novel: novel)
      expect(location.novel).to eq(novel)
    end
  end

  describe "callbacks" do
    it "sets last_updated_at on create" do
      location = create(:bible_location)
      expect(location.last_updated_at).to be_present
    end

    it "updates last_updated_at on update" do
      location = create(:bible_location)
      original = location.last_updated_at
      travel_to(1.minute.from_now) do
        location.update!(name: "New Place")
      end
      expect(location.last_updated_at).to be > original
    end
  end

  describe "scopes" do
    it "orders by name ascending with .by_name" do
      novel = create(:novel)
      zoo   = create(:bible_location, novel: novel, name: "Zoo")
      arena = create(:bible_location, novel: novel, name: "Arena")
      expect(novel.bible_locations.by_name).to eq([ arena, zoo ])
    end
  end

  describe "novel destroy cascade" do
    it "is destroyed when its novel is destroyed" do
      novel = create(:novel)
      create(:bible_location, novel: novel)
      expect { novel.destroy }.to change(BibleLocation, :count).by(-1)
    end
  end
end
