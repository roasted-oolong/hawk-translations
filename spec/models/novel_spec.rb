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
  end
end
