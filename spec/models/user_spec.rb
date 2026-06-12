require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      user = build(:user)
      expect(user).to be_valid
    end

    it "requires email" do
      user = build(:user, email: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "requires email to be unique" do
      create(:user, email: "test@example.com")
      user = build(:user, email: "test@example.com")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "requires name" do
      user = build(:user, name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:name]).to be_present
    end

    it "requires provider" do
      user = build(:user, provider: nil)
      expect(user).not_to be_valid
      expect(user.errors[:provider]).to be_present
    end

    it "requires uid" do
      user = build(:user, uid: nil)
      expect(user).not_to be_valid
      expect(user.errors[:uid]).to be_present
    end

    it "requires uid to be unique scoped to provider" do
      create(:user, provider: "google_oauth2", uid: "abc123")
      user = build(:user, provider: "google_oauth2", uid: "abc123")
      expect(user).not_to be_valid
    end

    it "allows the same uid for different providers" do
      create(:user, provider: "google_oauth2", uid: "abc123")
      user = build(:user, provider: "github", uid: "abc123")
      expect(user).to be_valid
    end
  end

  describe "defaults" do
    it "defaults platform_admin to false" do
      user = create(:user)
      expect(user.platform_admin).to be false
    end
  end

  describe ".from_omniauth" do
    # Duck-types OmniAuth::AuthHash (method-style access, mutable) — the
    # omniauth gem is not installed, so the real constant is unavailable here.
    let(:auth) do
      info = ActiveSupport::OrderedOptions.new
      info.email = "jenna@example.com"
      info.name  = "Jenna"

      ActiveSupport::OrderedOptions.new.tap do |a|
        a.provider = "google_oauth2"
        a.uid      = "123456789"
        a.info     = info
      end
    end

    context "when the user does not exist" do
      it "creates a new user" do
        expect { User.from_omniauth(auth) }.to change(User, :count).by(1)
      end

      it "sets provider, uid, email, and name from auth hash" do
        user = User.from_omniauth(auth)
        expect(user.provider).to eq("google_oauth2")
        expect(user.uid).to eq("123456789")
        expect(user.email).to eq("jenna@example.com")
        expect(user.name).to eq("Jenna")
      end
    end

    context "when the user already exists" do
      before { create(:user, provider: "google_oauth2", uid: "123456789", email: "jenna@example.com", name: "Jenna") }

      it "does not create a duplicate" do
        expect { User.from_omniauth(auth) }.not_to change(User, :count)
      end

      it "returns the existing user" do
        user = User.from_omniauth(auth)
        expect(user.email).to eq("jenna@example.com")
      end

      it "updates the name if it changed" do
        auth.info.name = "Jenna Updated"
        user = User.from_omniauth(auth)
        expect(user.name).to eq("Jenna Updated")
      end
    end
  end

  describe "#display_role" do
    context "when the user is a platform admin" do
      it "returns 'Platform Admin' regardless of memberships" do
        user = create(:user, platform_admin: true)
        create(:membership, user: user, role: "team_member")
        expect(user.display_role).to eq("Platform Admin")
      end
    end

    context "when the user has a team_admin membership" do
      it "returns 'Team Admin'" do
        user = create(:user, platform_admin: false)
        create(:membership, user: user, role: "team_admin")
        expect(user.display_role).to eq("Team Admin")
      end
    end

    context "when the user has only team_member memberships" do
      it "returns 'Team Member'" do
        user = create(:user, platform_admin: false)
        create(:membership, user: user, role: "team_member")
        expect(user.display_role).to eq("Team Member")
      end
    end

    context "when the user has both team_admin and team_member memberships" do
      it "returns 'Team Admin' (highest role wins)" do
        user = create(:user, platform_admin: false)
        create(:membership, user: user, role: "team_member")
        create(:membership, user: user, role: "team_admin")
        expect(user.display_role).to eq("Team Admin")
      end
    end

    context "when the user has no memberships" do
      it "returns 'No role assigned'" do
        user = create(:user, platform_admin: false)
        expect(user.display_role).to eq("No role assigned")
      end
    end
  end
end
