# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateEmbeddingJob, type: :job do
  let(:novel)     { create(:novel) }
  let(:character) { create(:bible_character, novel: novel, name: "Hyuk Kang", korean_name: "강혁") }
  let(:fake_vector) { Array.new(1024, 0.01) }

  before do
    allow(VoyageClient).to receive(:embed).and_return(fake_vector)
  end

  describe "#perform" do
    context "when no embedding exists for the record (fresh embed)" do
      it "calls VoyageClient.embed with the record's embeddable_text" do
        expect(VoyageClient).to receive(:embed).with(character.embeddable_text)
        described_class.new.perform("BibleCharacter", character.id)
      end

      it "creates a BibleEmbedding record" do
        expect {
          described_class.new.perform("BibleCharacter", character.id)
        }.to change(BibleEmbedding, :count).by(1)
      end

      it "stores the correct embeddable association" do
        described_class.new.perform("BibleCharacter", character.id)
        embedding = BibleEmbedding.find_by(embeddable: character)
        expect(embedding.embeddable).to eq(character)
      end

      it "stores the novel_id on the embedding" do
        described_class.new.perform("BibleCharacter", character.id)
        embedding = BibleEmbedding.find_by(embeddable: character)
        expect(embedding.novel_id).to eq(novel.id)
      end

      it "stores the organization_id on the embedding" do
        described_class.new.perform("BibleCharacter", character.id)
        embedding = BibleEmbedding.find_by(embeddable: character)
        expect(embedding.organization_id).to eq(novel.organization_id)
      end

      it "stores the content_hash as SHA256 of embeddable_text" do
        described_class.new.perform("BibleCharacter", character.id)
        embedding = BibleEmbedding.find_by(embeddable: character)
        expected_hash = Digest::SHA256.hexdigest(character.embeddable_text)
        expect(embedding.content_hash).to eq(expected_hash)
      end
    end

    context "when an embedding already exists with matching content_hash (no change)" do
      before do
        existing_hash = Digest::SHA256.hexdigest(character.embeddable_text)
        create(:bible_embedding,
               embeddable: character,
               novel: novel,
               content_hash: existing_hash)
      end

      it "does not call VoyageClient.embed" do
        expect(VoyageClient).not_to receive(:embed)
        described_class.new.perform("BibleCharacter", character.id)
      end

      it "does not create a new BibleEmbedding record" do
        expect {
          described_class.new.perform("BibleCharacter", character.id)
        }.not_to change(BibleEmbedding, :count)
      end
    end

    context "when an embedding exists with a stale content_hash (content changed)" do
      before do
        create(:bible_embedding,
               embeddable: character,
               novel: novel,
               content_hash: "stale_hash_from_old_content")
      end

      it "calls VoyageClient.embed with the updated embeddable_text" do
        expect(VoyageClient).to receive(:embed).with(character.embeddable_text)
        described_class.new.perform("BibleCharacter", character.id)
      end

      it "updates the existing BibleEmbedding record rather than creating a new one" do
        expect {
          described_class.new.perform("BibleCharacter", character.id)
        }.not_to change(BibleEmbedding, :count)
      end

      it "updates the content_hash to the current value" do
        described_class.new.perform("BibleCharacter", character.id)
        embedding = BibleEmbedding.find_by(embeddable: character)
        expected_hash = Digest::SHA256.hexdigest(character.embeddable_text)
        expect(embedding.content_hash).to eq(expected_hash)
      end
    end

    context "when the embeddable record no longer exists" do
      it "does nothing and does not raise" do
        expect {
          described_class.new.perform("BibleCharacter", 0)
        }.not_to raise_error
      end

      it "does not call VoyageClient.embed" do
        expect(VoyageClient).not_to receive(:embed)
        described_class.new.perform("BibleCharacter", 0)
      end
    end

    context "when VoyageClient raises ApiError" do
      before do
        allow(VoyageClient).to receive(:embed).and_raise(VoyageClient::ApiError, "rate limited")
      end

      it "re-raises the error so Solid Queue can retry the job" do
        expect {
          described_class.new.perform("BibleCharacter", character.id)
        }.to raise_error(VoyageClient::ApiError, "rate limited")
      end

      it "does not create a BibleEmbedding record" do
        expect {
          described_class.new.perform("BibleCharacter", character.id) rescue nil
        }.not_to change(BibleEmbedding, :count)
      end
    end
  end
end
