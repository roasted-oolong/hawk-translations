require "rails_helper"

RSpec.describe NovelTeamAssignment, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      assignment = build(:novel_team_assignment)
      expect(assignment).to be_valid
    end

    it "requires novel" do
      assignment = build(:novel_team_assignment, novel: nil)
      expect(assignment).not_to be_valid
      expect(assignment.errors[:novel]).to be_present
    end

    it "requires team" do
      assignment = build(:novel_team_assignment, team: nil)
      expect(assignment).not_to be_valid
      expect(assignment.errors[:team]).to be_present
    end

    it "requires permission_level" do
      assignment = build(:novel_team_assignment, permission_level: nil)
      expect(assignment).not_to be_valid
      expect(assignment.errors[:permission_level]).to be_present
    end

    it "rejects an invalid permission_level" do
      expect {
        build(:novel_team_assignment, permission_level: "superuser")
      }.to raise_error(ArgumentError)
    end

    it "enforces uniqueness of team within a novel" do
      novel = create(:novel)
      team  = create(:team, organization: novel.organization)
      create(:novel_team_assignment, novel: novel, team: team)
      duplicate = build(:novel_team_assignment, novel: novel, team: team)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:novel_id]).to be_present
    end

    it "allows the same team to be assigned to different novels" do
      org     = create(:organization)
      team    = create(:team, organization: org)
      novel_a = create(:novel, organization: org)
      novel_b = create(:novel, organization: org)
      create(:novel_team_assignment, novel: novel_a, team: team)
      second = build(:novel_team_assignment, novel: novel_b, team: team)
      expect(second).to be_valid
    end

    it "allows the same novel to be assigned to different teams" do
      org    = create(:organization)
      novel  = create(:novel, organization: org)
      team_a = create(:team, organization: org)
      team_b = create(:team, organization: org)
      create(:novel_team_assignment, novel: novel, team: team_a)
      second = build(:novel_team_assignment, novel: novel, team: team_b)
      expect(second).to be_valid
    end
  end

  describe "enums" do
    %w[viewer editor translator admin].each do |level|
      it "accepts permission_level: #{level}" do
        assignment = build(:novel_team_assignment, permission_level: level)
        expect(assignment).to be_valid
        expect(assignment.permission_level).to eq(level)
      end
    end
  end

  describe "associations" do
    it "belongs to a novel" do
      novel      = create(:novel)
      assignment = create(:novel_team_assignment, novel: novel)
      expect(assignment.novel).to eq(novel)
    end

    it "belongs to a team" do
      team       = create(:team)
      assignment = create(:novel_team_assignment, team: team)
      expect(assignment.team).to eq(team)
    end
  end

  describe "dependent destroy" do
    it "is destroyed when its novel is destroyed" do
      assignment = create(:novel_team_assignment)
      expect { assignment.novel.destroy }.to change(NovelTeamAssignment, :count).by(-1)
    end

    it "is destroyed when its team is destroyed" do
      assignment = create(:novel_team_assignment)
      expect { assignment.team.destroy }.to change(NovelTeamAssignment, :count).by(-1)
    end
  end
end
