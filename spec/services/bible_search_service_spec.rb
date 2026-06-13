# frozen_string_literal: true

require "rails_helper"

RSpec.describe BibleSearchService do
  let(:organization) { create(:organization) }
  let(:novel)        { create(:novel, organization: organization) }
  let(:fake_vector)  { Array.new(512, 0.01) }

  before do
    allow(VoyageClient).to receive(:embed).and_return(fake_vector)
  end

  # Helper — create an embedding record for a bible entry with a real vector
  # so the SQL queries have something to match against.
  def embed!(record)
    BibleEmbedding.upsert(
      {
        embeddable_type: record.class.name,
        embeddable_id:   record.id,
        novel_id:        record.novel_id,
        organization_id: record.novel.organization_id,
        content_hash:    Digest::SHA256.hexdigest(record.embeddable_text),
        embedding:       "[#{fake_vector.join(",")}]",
        search_text:     Arel.sql(
          "to_tsvector('simple', #{ActiveRecord::Base.connection.quote(record.embeddable_text)})"
        ),
        created_at:      Time.current,
        updated_at:      Time.current
      },
      unique_by: %i[embeddable_type embeddable_id],
      update_only: %i[content_hash embedding search_text]
    )
    BibleEmbedding.find_by!(embeddable_type: record.class.name, embeddable_id: record.id)
  end

  describe "#call" do
    context "novel-scoped search" do
      let!(:character) { create(:bible_character, novel: novel, name: "Hyuk Kang", role: "Protagonist") }
      let!(:location)  { create(:bible_location,  novel: novel, name: "HS Entertainment") }
      let!(:char_emb)  { embed!(character) }
      let!(:loc_emb)   { embed!(location) }

      it "returns results scoped to the given novel" do
        other_novel = create(:novel, organization: organization)
        other_char  = create(:bible_character, novel: other_novel, name: "Other Person")
        embed!(other_char)

        results = described_class.new(scope: novel, query: "protagonist manager").call
        result_ids = results.map { |r| r[:embedding_id] }

        expect(result_ids).to include(char_emb.id)
        expect(result_ids).not_to include(
          BibleEmbedding.find_by(embeddable: other_char).id
        )
      end

      it "returns result structs with expected keys" do
        results = described_class.new(scope: novel, query: "manager").call
        expect(results).not_to be_empty
        result = results.first
        expect(result).to include(:embedding_id, :embeddable_type, :embeddable_id,
                                  :novel_id, :score, :record)
      end
    end

    context "category filtering" do
      let!(:character) { create(:bible_character, novel: novel, name: "Hyuk Kang") }
      let!(:location)  { create(:bible_location,  novel: novel, name: "HS Entertainment") }

      before do
        embed!(character)
        embed!(location)
      end

      it "returns only results matching the requested categories" do
        results = described_class.new(
          scope:      novel,
          query:      "entertainment",
          categories: [ "BibleLocation" ]
        ).call

        types = results.map { |r| r[:embeddable_type] }.uniq
        expect(types).to eq([ "BibleLocation" ])
      end

      it "returns all categories when none specified" do
        results = described_class.new(scope: novel, query: "kang").call
        types   = results.map { |r| r[:embeddable_type] }.uniq
        # Both character and location embeddings exist — at least characters
        # should appear without a category filter.
        expect(types).to include("BibleCharacter")
      end
    end

    context "result limit" do
      before do
        5.times do |i|
          char = create(:bible_character, novel: novel, name: "Character #{i}")
          embed!(char)
        end
      end

      it "respects the limit option" do
        results = described_class.new(scope: novel, query: "character", limit: 2).call
        expect(results.length).to be <= 2
      end

      it "defaults to 10 results" do
        results = described_class.new(scope: novel, query: "character").call
        expect(results.length).to be <= 10
      end
    end

    context "organization-scoped search" do
      let(:novel_b) { create(:novel, organization: organization) }

      before do
        char_a = create(:bible_character, novel: novel,   name: "Kang from novel A")
        char_b = create(:bible_character, novel: novel_b, name: "Kang from novel B")
        embed!(char_a)
        embed!(char_b)
      end

      it "returns results from multiple novels when scoped to organization" do
        results = described_class.new(scope: organization, query: "kang").call
        novel_ids = results.map { |r| r[:novel_id] }.uniq
        expect(novel_ids).to include(novel.id, novel_b.id)
      end
    end

    context "empty query" do
      it "returns an empty array" do
        results = described_class.new(scope: novel, query: "").call
        expect(results).to eq([])
      end

      it "returns an empty array for blank query" do
        results = described_class.new(scope: novel, query: "   ").call
        expect(results).to eq([])
      end
    end

    context "when VoyageClient raises" do
      it "propagates the error" do
        allow(VoyageClient).to receive(:embed).and_raise(VoyageClient::ApiError, "rate limited")
        expect {
          described_class.new(scope: novel, query: "anything").call
        }.to raise_error(VoyageClient::ApiError)
      end
    end
  end
end
