# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProvisionWorkspace do
  subject(:service) { described_class.new(user) }

  let(:user) { create(:user) }

  describe "#call" do
    context "when the user has no existing workspace" do
      it "creates an Organization" do
        expect { service.call }.to change(Organization, :count).by(1)
      end

      it "names the organization after the user" do
        service.call
        expect(Organization.last.name).to eq(user.name)
      end

      it "creates a default Team inside that organization" do
        service.call
        org = Organization.last
        expect(org.teams.count).to eq(1)
      end

      it "names the default team 'Default Team'" do
        service.call
        expect(Organization.last.teams.first.name).to eq("Default Team")
      end

      it "creates a Membership joining the user to that team" do
        expect { service.call }.to change(Membership, :count).by(1)
      end

      it "assigns the team_admin role on the membership" do
        service.call
        membership = user.memberships.first
        expect(membership).to be_team_admin
      end

      it "returns the user" do
        result = service.call
        expect(result).to eq(user)
      end
    end

    context "when the user already has a team membership" do
      before do
        # Simulate an already-provisioned workspace
        org  = create(:organization)
        team = create(:team, organization: org)
        create(:membership, user: user, team: team, role: "team_admin")
      end

      it "does not create another Organization" do
        expect { service.call }.not_to change(Organization, :count)
      end

      it "does not create another Team" do
        expect { service.call }.not_to change(Team, :count)
      end

      it "does not create another Membership" do
        expect { service.call }.not_to change(Membership, :count)
      end

      it "returns the user" do
        expect(service.call).to eq(user)
      end
    end
  end
end
