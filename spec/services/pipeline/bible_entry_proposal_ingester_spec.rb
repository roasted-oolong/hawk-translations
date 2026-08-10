require "rails_helper"

RSpec.describe Pipeline::BibleEntryProposalIngester do
  let(:novel) { create(:novel) }
  let(:ingester) { described_class.new(novel) }

  let!(:chapter76) { create(:chapter, novel: novel, number: 76) }
  let!(:chapter77) { create(:chapter, novel: novel, number: 77) }

  def sections(characters: nil)
    { characters: characters, locations: nil, terminology: nil, cultural_phrases: nil, story: nil }
  end

  describe "#ingest_batch" do
    it "creates a proposal for a brand-new entry" do
      content = "## New Character (신규)\n- Role: Extra\n- First appearance: 77\n"

      expect {
        ingester.ingest_batch(sections(characters: content), [ 76, 77 ])
      }.to change(BibleEntryProposal, :count).by(1)

      proposal = BibleEntryProposal.last
      expect(proposal.entry_type).to eq("character")
      expect(proposal.existing_record_id).to be_nil
      expect(proposal.fields["role"]).to eq("Extra")
    end

    it "creates a proposal for a changed existing entry, carrying existing_record_id" do
      character = create(:bible_character, novel: novel, name: "Sung-ah", korean_name: "성아", role: "Old role")
      content = "## Sung-ah (성아)\n- Korean name: 성아\n- Role: New role\n"

      ingester.ingest_batch(sections(characters: content), [ 76, 77 ])

      proposal = BibleEntryProposal.last
      expect(proposal.existing_record_id).to eq(character.id)
      expect(proposal.fields["role"]).to eq("New role")
    end

    it "creates no proposal when the entry matches an existing record with no differences" do
      create(:bible_character, novel: novel, name: "Sung-ah", korean_name: "성아", role: "Lead")
      content = "## Sung-ah (성아)\n- Korean name: 성아\n- Role: Lead\n"

      expect {
        ingester.ingest_batch(sections(characters: content), [ 76, 77 ])
      }.not_to change(BibleEntryProposal, :count)
    end

    it "creates no proposal for a dismissed korean_key" do
      novel.update_column(:preread_dismissed_keys, '["characters:성아"]')
      content = "## Sung-ah (성아)\n- Korean name: 성아\n- Role: Lead\n"

      expect {
        ingester.ingest_batch(sections(characters: content), [ 76, 77 ])
      }.not_to change(BibleEntryProposal, :count)
    end

    it "returns :empty for a blank section, :no_new_entries for an all-dismissed section, :written otherwise" do
      novel.update_column(:preread_dismissed_keys, '["locations:성아"]')
      dismissed_content = "## Sung-ah (성아)\n- Korean name: 성아\n"
      new_content        = "## New Character (신규)\n- Role: Extra\n"

      result = ingester.ingest_batch(
        { characters: new_content, locations: dismissed_content, terminology: nil,
          cultural_phrases: "", story: nil },
        [ 76, 77 ]
      )

      expect(result[:characters]).to eq(:written)
      expect(result[:locations]).to eq(:no_new_entries)
      expect(result[:terminology]).to eq(:empty)
      expect(result[:cultural_phrases]).to eq(:empty)
      expect(result[:story]).to eq(:empty)
    end

    describe "chapter attribution" do
      it "attributes to the parsed first_appearance_chapter when it falls within the batch" do
        content = "## New Character (신규)\n- Role: Extra\n- First appearance: 76\n"
        ingester.ingest_batch(sections(characters: content), [ 76, 77 ])
        expect(BibleEntryProposal.last.chapter).to eq(chapter76)
      end

      it "falls back to the batch's last chapter when first_appearance_chapter is out of the batch's range" do
        content = "## New Character (신규)\n- Role: Extra\n- First appearance: 5\n"
        ingester.ingest_batch(sections(characters: content), [ 76, 77 ])
        expect(BibleEntryProposal.last.chapter).to eq(chapter77)
      end

      it "falls back to the batch's last chapter when there is no parsed chapter field (e.g. locations)" do
        content = "## HS Entertainment (HS엔터테인먼트)\n- Significance: Main label.\n"
        ingester.ingest_batch(sections(characters: nil).merge(locations: content), [ 76, 77 ])
        expect(BibleEntryProposal.last.chapter).to eq(chapter77)
      end
    end

    describe "idempotency" do
      it "does not create a duplicate row when the same batch is ingested twice" do
        content = "## New Character (신규)\n- Role: Extra\n"
        ingester.ingest_batch(sections(characters: content), [ 76, 77 ])

        expect {
          ingester.ingest_batch(sections(characters: content), [ 76, 77 ])
        }.not_to change(BibleEntryProposal, :count)
      end

      it "updates a still-pending proposal's fields on a later run" do
        first_pass  = "## New Character (신규)\n- Role: Extra\n"
        second_pass = "## New Character (신규)\n- Role: Updated role\n"
        ingester.ingest_batch(sections(characters: first_pass), [ 76, 77 ])

        expect {
          ingester.ingest_batch(sections(characters: second_pass), [ 76, 77 ])
        }.not_to change(BibleEntryProposal, :count)

        expect(BibleEntryProposal.last.fields["role"]).to eq("Updated role")
      end

      it "re-finds and updates instead of raising when a RecordNotUnique race occurs" do
        content = "## New Character (신규)\n- Role: Extra\n"
        korean_key = Pipeline::BibleUtils.normalize_korean("신규")

        # Pre-create the row a concurrent ingestion would have raced in.
        raced_row = create(:bible_entry_proposal, novel: novel, chapter: chapter77,
                            entry_type: "character", korean_key: korean_key, fields: { "role" => "Extra" })

        # Simulate the race window: find_or_initialize_by returns a
        # brand-new unsaved record (as if its SELECT ran before the other
        # process's INSERT landed) even though a row for this
        # [novel, entry_type, korean_key] already exists — #save! then
        # genuinely hits the DB's unique index, no mocked exception.
        allow_any_instance_of(ActiveRecord::Associations::CollectionProxy)
          .to receive(:find_or_initialize_by)
          .and_return(BibleEntryProposal.new(novel: novel, entry_type: "character", korean_key: korean_key))

        expect {
          ingester.ingest_batch(sections(characters: content), [ 76, 77 ])
        }.not_to raise_error

        expect(BibleEntryProposal.count).to eq(1)
        expect(raced_row.reload.fields["role"]).to eq("Extra")
      end
    end
  end
end
