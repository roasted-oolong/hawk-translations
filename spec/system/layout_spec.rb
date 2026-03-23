require "rails_helper"

# M14 — Application Layout, Navigation & Login Page
#
# Covers:
#   1. Login page renders with expected elements
#   2. Sidebar renders on every authenticated page (renamed from app-nav at M19)
#   3. Sign-out works and redirects to login

RSpec.describe "M14 Layout, Navigation & Login", type: :system do
  # ---------------------------------------------------------------------------
  # Login page
  # ---------------------------------------------------------------------------
  describe "login page" do
    before { visit login_path }

    it "renders the app name" do
      expect(page).to have_text("Hawk Translations")
    end

    it "renders the sign-in button" do
      expect(page).to have_button("Sign in with Google")
    end

    it "has no sidebar" do
      expect(page).not_to have_selector("[data-testid='app-sidebar']")
    end

    it "shows an alert when present" do
      visit "/auth/failure?message=access_denied"
      expect(page).to have_selector("[data-testid='flash-alert']")
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar — present on every authenticated page
  # ---------------------------------------------------------------------------
  describe "navigation" do
    let(:user) { create(:user) }

    before do
      mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
      visit "/auth/google_oauth2/callback"
    end

    it "renders the sidebar on the dashboard" do
      expect(page).to have_selector("[data-testid='app-sidebar']")
    end

    it "shows the app name in the sidebar" do
      within "[data-testid='app-sidebar']" do
        expect(page).to have_text("Hawk")
      end
    end

    it "shows a sign-out button in the topbar" do
      within "[data-testid='app-topbar']" do
        expect(page).to have_button("Sign out")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Sign-out
  # ---------------------------------------------------------------------------
  describe "sign-out" do
    let(:user) { create(:user) }

    before do
      mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
      visit "/auth/google_oauth2/callback"
    end

    it "redirects to login after signing out" do
      within "[data-testid='app-topbar']" do
        click_button "Sign out"
      end
      expect(page).to have_current_path(login_path)
    end

    it "shows a confirmation notice after signing out" do
      within "[data-testid='app-topbar']" do
        click_button "Sign out"
      end
      expect(page).to have_selector("[data-testid='flash-notice']")
    end
  end
end
