require "rails_helper"

RSpec.describe Membership, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      membership = build(:membership)
      expect(membership).to be_valid
    end

    it "requires user" do
      membership = build(:membership, user: nil)
      expect(membership).not_to be_valid
      expect(membership.errors[:user]).to be_present
    end

    it "requires team" do
      membership = build(:membership, team: nil)
      expect(membership).not_to be_valid
      expect(membership.errors[:team]).to be_present
    end

    it "requires role" do
      membership = build(:membership, role: nil)
      expect(membership).not_to be_valid
      expect(membership.errors[:role]).to be_present
    end

    it "rejects an invalid role" do
      expect {
        build(:membership, role: "superuser")
      }.to raise_error(ArgumentError)
    end

    it "enforces uniqueness of user within a team" do
      user = create(:user)
      team = create(:team)
      create(:membership, user: user, team: team)
      duplicate = build(:membership, user: user, team: team)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to be_present
    end

    it "allows the same user to belong to different teams" do
      user = create(:user)
      team_a = create(:team)
      team_b = create(:team)
      create(:membership, user: user, team: team_a)
      second = build(:membership, user: user, team: team_b)
      expect(second).to be_valid
    end
  end

  describe "enums" do
    it "accepts team_admin role" do
      membership = build(:membership, role: "team_admin")
      expect(membership).to be_valid
      expect(membership.role).to eq("team_admin")
    end

    it "accepts team_member role" do
      membership = build(:membership, role: "team_member")
      expect(membership).to be_valid
      expect(membership.role).to eq("team_member")
    end
  end

  describe "associations" do
    it "belongs to a user" do
      user = create(:user)
      membership = create(:membership, user: user)
      expect(membership.user).to eq(user)
    end

    it "belongs to a team" do
      team = create(:team)
      membership = create(:membership, team: team)
      expect(membership.team).to eq(team)
    end
  end
end
