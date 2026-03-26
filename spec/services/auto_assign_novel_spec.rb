# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutoAssignNovel do
  subject(:service) { described_class.new(novel, user) }

  let(:org)   { create(:organization) }
  let(:team)  { create(:team, organization: org) }
  let(:user)  { create(:user) }
  let(:novel) { create(:novel, organization: org) }

  before do
    create(:membership, user: user, team: team, role: "team_admin")
  end

  describe "#call" do
    context "when the user has a team" do
      it "creates a NovelTeamAssignment" do
        expect { service.call }.to change(NovelTeamAssignment, :count).by(1)
      end

      it "assigns the novel to the user's first team" do
        service.call
        assignment = NovelTeamAssignment.last
        expect(assignment.team).to eq(user.teams.first)
      end

      it "sets permission_level to translator" do
        service.call
        assignment = NovelTeamAssignment.last
        expect(assignment).to be_translator
      end

      it "returns the novel" do
        expect(service.call).to eq(novel)
      end
    end

    context "when an assignment already exists for that team" do
      before do
        create(:novel_team_assignment, novel: novel, team: team, permission_level: "translator")
      end

      it "does not create a duplicate assignment" do
        expect { service.call }.not_to change(NovelTeamAssignment, :count)
      end

      it "returns the novel" do
        expect(service.call).to eq(novel)
      end
    end

    context "when the user has no teams" do
      let(:user_without_team) { create(:user) }

      subject(:service) { described_class.new(novel, user_without_team) }

      it "does not create an assignment" do
        expect { service.call }.not_to change(NovelTeamAssignment, :count)
      end

      it "returns the novel" do
        expect(service.call).to eq(novel)
      end
    end
  end
end
