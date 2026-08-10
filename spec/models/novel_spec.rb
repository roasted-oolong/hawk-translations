require "rails_helper"

RSpec.describe Novel, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      novel = build(:novel)
      expect(novel).to be_valid
    end

    it "requires title" do
      novel = build(:novel, title: nil)
      expect(novel).not_to be_valid
      expect(novel.errors[:title]).to be_present
    end

    it "requires directory_name" do
      novel = build(:novel, directory_name: nil)
      expect(novel).not_to be_valid
      expect(novel.errors[:directory_name]).to be_present
    end

    it "requires directory_name to be unique within an organization" do
      org = create(:organization)
      create(:novel, organization: org, directory_name: "idols-rewind")
      duplicate = build(:novel, organization: org, directory_name: "idols-rewind")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:directory_name]).to be_present
    end

    it "allows the same directory_name in different organizations" do
      create(:novel, directory_name: "my-novel")
      other_org = create(:organization)
      novel = build(:novel, organization: other_org, directory_name: "my-novel")
      expect(novel).to be_valid
    end

    it "requires organization" do
      novel = build(:novel, organization: nil)
      expect(novel).not_to be_valid
      expect(novel.errors[:organization]).to be_present
    end

    it "rejects an invalid visibility value" do
      expect {
        build(:novel, visibility: "public")
      }.to raise_error(ArgumentError)
    end

    it "defaults visibility to discoverable" do
      novel = create(:novel)
      expect(novel.visibility).to eq("discoverable")
    end

    # --- M21: cover_art attachment validations ---

    it "is valid without a cover_art attachment" do
      novel = create(:novel)
      expect(novel).to be_valid
    end

    it "rejects cover_art with an invalid content type" do
      novel = build(:novel)
      novel.cover_art.attach(
        io: StringIO.new("fake gif data"),
        filename: "cover.gif",
        content_type: "image/gif"
      )
      expect(novel).not_to be_valid
      expect(novel.errors[:cover_art]).to be_present
    end

    it "rejects cover_art larger than 5MB" do
      novel = build(:novel)
      novel.cover_art.attach(
        io: StringIO.new("x" * (5.megabytes + 1)),
        filename: "cover.jpg",
        content_type: "image/jpeg"
      )
      expect(novel).not_to be_valid
      expect(novel.errors[:cover_art]).to be_present
    end
  end

  describe "enums" do
    it "accepts discoverable visibility" do
      novel = build(:novel, visibility: "discoverable")
      expect(novel).to be_valid
    end

    it "accepts hidden visibility" do
      novel = build(:novel, visibility: "hidden")
      expect(novel).to be_valid
    end
  end

  describe "associations" do
    it "belongs to an organization" do
      org = create(:organization)
      novel = create(:novel, organization: org)
      expect(novel.organization).to eq(org)
    end

    it "belongs to a series optionally" do
      novel = create(:novel, series: nil)
      expect(novel.series).to be_nil
    end

    it "belongs to a series when assigned" do
      series = create(:series)
      novel = create(:novel, organization: series.organization, series: series)
      expect(novel.series).to eq(series)
    end

    it "has an optional poc_user" do
      novel = create(:novel, poc_user: nil)
      expect(novel.poc_user).to be_nil
    end

    it "belongs to a poc_user when assigned" do
      user = create(:user)
      novel = create(:novel, poc_user: user)
      expect(novel.poc_user).to eq(user)
    end

    it "has many translation_jobs and destroys them on deletion" do
      novel = create(:novel)
      user  = create(:user)
      create(:translation_job, novel: novel, user: user)
      expect { novel.destroy }.to change(TranslationJob, :count).by(-1)
    end

    it "has many bible_entry_proposals and destroys them on deletion" do
      novel_dir = Dir.mktmpdir
      orig_root = ENV["HAWK_PROJECT_ROOT"]
      ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)

      novel = create(:novel, directory_name: File.basename(novel_dir))
      create(:bible_entry_proposal, novel: novel)
      expect { novel.destroy }.to change(BibleEntryProposal, :count).by(-1)
    ensure
      ENV["HAWK_PROJECT_ROOT"] = orig_root
      FileUtils.rm_rf(novel_dir)
    end
  end

  describe "#append_preread_dismissed_key!" do
    it "adds a key to an empty preread_dismissed_keys" do
      novel = create(:novel)
      novel.append_preread_dismissed_key!("character:sung-ah")
      expect(JSON.parse(novel.reload.preread_dismissed_keys)).to eq([ "character:sung-ah" ])
    end

    it "appends onto existing keys without dropping them" do
      novel = create(:novel, preread_dismissed_keys: [ "character:kang" ].to_json)
      novel.append_preread_dismissed_key!("location:hs-entertainment")
      expect(JSON.parse(novel.reload.preread_dismissed_keys))
        .to contain_exactly("character:kang", "location:hs-entertainment")
    end

    it "de-duplicates repeated keys" do
      novel = create(:novel, preread_dismissed_keys: [ "character:kang" ].to_json)
      novel.append_preread_dismissed_key!("character:kang")
      expect(JSON.parse(novel.reload.preread_dismissed_keys)).to eq([ "character:kang" ])
    end

    it "accepts multiple keys at once" do
      novel = create(:novel)
      novel.append_preread_dismissed_key!("character:a", "character:b")
      expect(JSON.parse(novel.reload.preread_dismissed_keys)).to contain_exactly("character:a", "character:b")
    end

    it "recovers from unparseable existing JSON rather than raising" do
      novel = create(:novel, preread_dismissed_keys: "not json")
      novel.append_preread_dismissed_key!("character:kang")
      expect(JSON.parse(novel.reload.preread_dismissed_keys)).to eq([ "character:kang" ])
    end
  end

  describe "#pending_preread_breakdown" do
    it "returns a zero total and empty by_category with no proposals" do
      novel = create(:novel)
      result = novel.pending_preread_breakdown
      expect(result).to eq(total: 0, by_category: {})
    end

    it "sums per-entry_type counts into a total" do
      novel = create(:novel)
      create(:bible_entry_proposal, novel: novel, entry_type: "character", korean_key: "a")
      create(:bible_entry_proposal, novel: novel, entry_type: "character", korean_key: "b")
      create(:bible_entry_proposal, novel: novel, entry_type: "location", korean_key: "c")

      result = novel.pending_preread_breakdown

      expect(result[:total]).to eq(3)
      expect(result[:by_category]).to eq("character" => 2, "location" => 1)
    end

    it "does not count another novel's proposals" do
      novel = create(:novel)
      create(:bible_entry_proposal, novel: create(:novel))

      expect(novel.pending_preread_breakdown[:total]).to eq(0)
    end
  end
end
