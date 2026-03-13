require "rails_helper"

RSpec.describe Team, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      team = build(:team)
      expect(team).to be_valid
    end

    it "requires name" do
      team = build(:team, name: nil)
      expect(team).not_to be_valid
      expect(team.errors[:name]).to be_present
    end

    it "requires organization" do
      team = build(:team, organization: nil)
      expect(team).not_to be_valid
      expect(team.errors[:organization]).to be_present
    end
  end

  describe "associations" do
    it "belongs to an organization" do
      org = create(:organization)
      team = create(:team, organization: org)
      expect(team.organization).to eq(org)
    end

    it "has many memberships" do
      team = create(:team)
      membership = create(:membership, team: team)
      expect(team.memberships).to include(membership)
    end

    it "has many users through memberships" do
      team = create(:team)
      user = create(:user)
      create(:membership, team: team, user: user)
      expect(team.users).to include(user)
    end

    it "destroys dependent memberships when destroyed" do
      team = create(:team)
      create(:membership, team: team)
      expect { team.destroy }.to change(Membership, :count).by(-1)
    end
  end
end
