# frozen_string_literal: true

require "rails_helper"

RSpec.describe BibleEmbedding, type: :model do
  describe "associations" do
    it "belongs to a novel" do
      novel     = create(:novel)
      character = create(:bible_character, novel: novel)
      embedding = create(:bible_embedding, embeddable: character, novel: novel)
      expect(embedding.novel).to eq(novel)
    end

    it "belongs to an organization" do
      novel     = create(:novel)
      character = create(:bible_character, novel: novel)
      embedding = create(:bible_embedding, embeddable: character, novel: novel)
      expect(embedding.organization).to eq(novel.organization)
    end

    it "returns the embeddable record via polymorphic association" do
      novel     = create(:novel)
      character = create(:bible_character, novel: novel)
      embedding = create(:bible_embedding, embeddable: character, novel: novel)
      expect(embedding.embeddable).to eq(character)
    end
  end

  describe "validations" do
    it "is valid with all required attributes" do
      novel     = create(:novel)
      character = create(:bible_character, novel: novel)
      embedding = build(:bible_embedding, embeddable: character, novel: novel)
      expect(embedding).to be_valid
    end

    it "requires embeddable_type" do
      embedding = build(:bible_embedding, embeddable_type: nil)
      expect(embedding).not_to be_valid
      expect(embedding.errors[:embeddable_type]).to be_present
    end

    it "requires embeddable_id" do
      embedding = build(:bible_embedding, embeddable_id: nil)
      expect(embedding).not_to be_valid
      expect(embedding.errors[:embeddable_id]).to be_present
    end

    it "requires novel" do
      embedding = build(:bible_embedding, novel: nil)
      expect(embedding).not_to be_valid
      expect(embedding.errors[:novel]).to be_present
    end

    it "requires organization" do
      embedding = build(:bible_embedding, organization: nil)
      expect(embedding).not_to be_valid
      expect(embedding.errors[:organization]).to be_present
    end

    it "requires content_hash" do
      embedding = build(:bible_embedding, content_hash: nil)
      expect(embedding).not_to be_valid
      expect(embedding.errors[:content_hash]).to be_present
    end

    it "enforces uniqueness of (embeddable_type, embeddable_id)" do
      novel     = create(:novel)
      character = create(:bible_character, novel: novel)
      create(:bible_embedding, embeddable: character, novel: novel)
      duplicate = build(:bible_embedding, embeddable: character, novel: novel)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:embeddable_id]).to be_present
    end
  end

  describe "scopes" do
    describe ".for_novel" do
      it "returns only embeddings belonging to the given novel" do
        novel_a = create(:novel)
        novel_b = create(:novel)
        char_a  = create(:bible_character, novel: novel_a)
        char_b  = create(:bible_character, novel: novel_b)
        emb_a   = create(:bible_embedding, embeddable: char_a, novel: novel_a)
        _emb_b  = create(:bible_embedding, embeddable: char_b, novel: novel_b)
        expect(BibleEmbedding.for_novel(novel_a)).to contain_exactly(emb_a)
      end
    end

    describe ".for_organization" do
      it "returns only embeddings belonging to the given organization" do
        novel_a = create(:novel)
        novel_b = create(:novel) # belongs to a different org via factory
        char_a  = create(:bible_character, novel: novel_a)
        char_b  = create(:bible_character, novel: novel_b)
        emb_a   = create(:bible_embedding, embeddable: char_a, novel: novel_a)
        _emb_b  = create(:bible_embedding, embeddable: char_b, novel: novel_b)
        expect(BibleEmbedding.for_organization(novel_a.organization)).to contain_exactly(emb_a)
      end
    end

    describe ".for_categories" do
      it "returns embeddings whose embeddable_type is in the given list" do
        novel  = create(:novel)
        char   = create(:bible_character, novel: novel)
        loc    = create(:bible_location,  novel: novel)
        emb_c  = create(:bible_embedding, embeddable: char, novel: novel)
        _emb_l = create(:bible_embedding, embeddable: loc,  novel: novel)
        result = BibleEmbedding.for_categories(["BibleCharacter"])
        expect(result).to contain_exactly(emb_c)
      end
    end
  end

  describe ".stale_for?" do
    it "returns true when no embedding record exists for the embeddable" do
      novel     = create(:novel)
      character = create(:bible_character, novel: novel)
      expect(BibleEmbedding.stale_for?(character, "somehash")).to be true
    end

    it "returns true when the existing content_hash differs" do
      novel     = create(:novel)
      character = create(:bible_character, novel: novel)
      create(:bible_embedding, embeddable: character, novel: novel, content_hash: "oldhash")
      expect(BibleEmbedding.stale_for?(character, "newhash")).to be true
    end

    it "returns false when the existing content_hash matches" do
      novel     = create(:novel)
      character = create(:bible_character, novel: novel)
      create(:bible_embedding, embeddable: character, novel: novel, content_hash: "abc123")
      expect(BibleEmbedding.stale_for?(character, "abc123")).to be false
    end
  end
end
