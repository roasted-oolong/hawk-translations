# Integration tier of R2's three-layer test strategy: real database, real
# BibleSearchService, real formatter output — no LLM involved. Only
# VoyageClient is stubbed (matching spec/services/bible_search_service_spec.rb's
# own pattern), since embedding generation calls a real external API.
require "rails_helper"

RSpec.describe Pipeline::Skills::BibleLookup, "integration" do
  let(:organization) { create(:organization) }
  let!(:novel)        { create(:novel, organization: organization, directory_name: "idols-rewind") }
  let(:fake_vector)   { Array.new(512, 0.01) }
  let(:skill)         { described_class.new(novel_directory_name: "idols-rewind") }

  before do
    allow(VoyageClient).to receive(:embed).and_return(fake_vector)
  end

  def embed!(record)
    BibleEmbedding.upsert(
      {
        embeddable_type: record.class.name,
        embeddable_id:   record.id,
        novel_id:        record.novel_id,
        organization_id: record.novel.organization_id,
        content_hash:    Digest::SHA256.hexdigest(record.embeddable_text),
        embedding:       "[#{fake_vector.join(',')}]",
        search_text:     Arel.sql(
          "to_tsvector('simple', #{ActiveRecord::Base.connection.quote(record.embeddable_text)})"
        ),
        created_at:      Time.current,
        updated_at:      Time.current
      },
      unique_by: %i[embeddable_type embeddable_id],
      update_only: %i[content_hash embedding search_text]
    )
  end

  it "resolves the novel by directory_name, searches, and formats real records — zero HTTP" do
    character = create(:bible_character, novel: novel, name: "Hyuk Kang", role: "Protagonist")
    embed!(character)

    output = skill.execute("query" => "Hyuk Kang")

    expect(output).to include("[Character]")
    expect(output).to include("Name: Hyuk Kang")
    expect(output).to include("Role: Protagonist")
  end

  it "returns a not-found message for a query with no matches in this novel" do
    output = skill.execute("query" => "nobody at all")

    expect(output).to eq("No bible entries found for: nobody at all")
  end

  it "scopes results to the resolved novel only" do
    other_novel = create(:novel, organization: organization, directory_name: "other-novel")
    other_character = create(:bible_character, novel: other_novel, name: "Someone Else")
    embed!(other_character)

    output = skill.execute("query" => "Someone Else")

    expect(output).to eq("No bible entries found for: Someone Else")
  end

  it "returns an error string, not an exception, when the novel directory doesn't exist" do
    missing = described_class.new(novel_directory_name: "does-not-exist")

    expect { missing.execute("query" => "anything") }.not_to raise_error
    expect(missing.execute("query" => "anything")).to match(/\A\[bible_lookup error: could not resolve novel/)
  end
end
