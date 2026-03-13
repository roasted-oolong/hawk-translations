require "rails_helper"

RSpec.describe Organization, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      org = build(:organization)
      expect(org).to be_valid
    end

    it "requires name" do
      org = build(:organization, name: nil)
      expect(org).not_to be_valid
      expect(org.errors[:name]).to be_present
    end
  end

  describe "associations" do
    it "has many teams" do
      org = create(:organization)
      team = create(:team, organization: org)
      expect(org.teams).to include(team)
    end

    it "has many series" do
      org = create(:organization)
      series = create(:series, organization: org)
      expect(org.series).to include(series)
    end

    it "has many novels" do
      org = create(:organization)
      novel = create(:novel, organization: org)
      expect(org.novels).to include(novel)
    end

    it "destroys dependent teams when destroyed" do
      org = create(:organization)
      create(:team, organization: org)
      expect { org.destroy }.to change(Team, :count).by(-1)
    end

    it "destroys dependent series when destroyed" do
      org = create(:organization)
      create(:series, organization: org)
      expect { org.destroy }.to change(Series, :count).by(-1)
    end

    it "destroys dependent novels when destroyed" do
      org = create(:organization)
      create(:novel, organization: org)
      expect { org.destroy }.to change(Novel, :count).by(-1)
    end
  end
end
