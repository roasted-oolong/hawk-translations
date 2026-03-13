require "rails_helper"

RSpec.describe Series, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      series = build(:series)
      expect(series).to be_valid
    end

    it "requires name" do
      series = build(:series, name: nil)
      expect(series).not_to be_valid
      expect(series.errors[:name]).to be_present
    end

    it "requires organization" do
      series = build(:series, organization: nil)
      expect(series).not_to be_valid
      expect(series.errors[:organization]).to be_present
    end
  end

  describe "associations" do
    it "belongs to an organization" do
      org = create(:organization)
      series = create(:series, organization: org)
      expect(series.organization).to eq(org)
    end

    it "has many novels" do
      series = create(:series)
      novel = create(:novel, organization: series.organization, series: series)
      expect(series.novels).to include(novel)
    end

    it "nullifies novel series_id when destroyed" do
      series = create(:series)
      novel = create(:novel, organization: series.organization, series: series)
      series.destroy
      expect(novel.reload.series_id).to be_nil
    end
  end
end
