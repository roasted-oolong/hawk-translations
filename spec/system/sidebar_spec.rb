# spec/system/m19_sidebar_spec.rb
#
# M19 — Sidebar Navigation
#
# Two-element app shell:
#   - Fixed left sidebar  (data-testid="app-sidebar")    — desktop primary nav
#   - Fixed slim topbar   (data-testid="app-topbar")     — breadcrumb, user, sign-out
#   - Fixed bottom nav    (data-testid="app-bottom-nav") — mobile primary nav
#
# Covers:
#   1. Sidebar renders on every authenticated page
#   2. Topbar renders on every authenticated page
#   3. Sidebar and topbar absent on the login page
#   4. Sign-out is reachable from the topbar
#   5. Dashboard link in sidebar navigates correctly
#   6. Novels link in sidebar navigates correctly
#   7. Bottom nav in DOM on authenticated pages, absent on login
#   8. Bottom nav links navigate correctly

RSpec.describe "M19 Sidebar Navigation", type: :system do
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  # ---------------------------------------------------------------------------
  # 1. Sidebar renders on every authenticated page
  # ---------------------------------------------------------------------------
  describe "sidebar presence" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "renders the sidebar on the dashboard" do
      visit root_path
      expect(page).to have_selector("[data-testid='app-sidebar']")
    end

    it "renders the sidebar on the novel index" do
      visit novels_path
      expect(page).to have_selector("[data-testid='app-sidebar']")
    end

    it "renders the sidebar on a novel show page" do
      org   = create(:organization)
      team  = create(:team, organization: org)
      create(:membership, user: user, team: team)
      novel = create(:novel, organization: org)

      visit novel_path(novel)
      expect(page).to have_selector("[data-testid='app-sidebar']")
    end

    it "shows the brand mark inside the sidebar" do
      visit root_path
      within "[data-testid='app-sidebar']" do
        expect(page).to have_text("Hawk")
      end
    end

    it "shows the Dashboard nav link inside the sidebar" do
      visit root_path
      within "[data-testid='app-sidebar']" do
        expect(page).to have_link("Dashboard")
      end
    end

    it "shows the Novels nav link inside the sidebar" do
      visit root_path
      within "[data-testid='app-sidebar']" do
        expect(page).to have_link("Novels")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Topbar renders on every authenticated page
  # ---------------------------------------------------------------------------
  describe "topbar presence" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "renders the topbar on the dashboard" do
      visit root_path
      expect(page).to have_selector("[data-testid='app-topbar']")
    end

    it "renders the topbar on the novel index" do
      visit novels_path
      expect(page).to have_selector("[data-testid='app-topbar']")
    end

    it "renders the topbar on a novel show page" do
      org   = create(:organization)
      team  = create(:team, organization: org)
      create(:membership, user: user, team: team)
      novel = create(:novel, organization: org)

      visit novel_path(novel)
      expect(page).to have_selector("[data-testid='app-topbar']")
    end

    it "shows the user name in the topbar" do
      visit root_path
      within "[data-testid='app-topbar']" do
        expect(page).to have_text(user.name)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Sidebar and topbar absent on the login page
  # ---------------------------------------------------------------------------
  describe "login page" do
    before { visit login_path }

    it "does not render the sidebar on the login page" do
      expect(page).not_to have_selector("[data-testid='app-sidebar']")
    end

    it "does not render the topbar on the login page" do
      expect(page).not_to have_selector("[data-testid='app-topbar']")
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Sign-out is reachable from the topbar
  # ---------------------------------------------------------------------------
  describe "sign-out via topbar" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "shows a sign-out button in the topbar" do
      visit root_path
      within "[data-testid='app-topbar']" do
        expect(page).to have_button("Sign out")
      end
    end

    it "redirects to login after clicking sign-out" do
      visit root_path
      within "[data-testid='app-topbar']" do
        click_button "Sign out"
      end
      expect(page).to have_current_path(login_path)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Dashboard link navigates correctly
  # ---------------------------------------------------------------------------
  describe "Dashboard nav link" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "navigates to the dashboard" do
      visit novels_path
      within "[data-testid='app-sidebar']" do
        click_link "Dashboard"
      end
      expect(page).to have_current_path(root_path)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Novels link navigates correctly
  # ---------------------------------------------------------------------------
  describe "Novels nav link" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "navigates to the novel index" do
      visit root_path
      within "[data-testid='app-sidebar']" do
        click_link "Novels"
      end
      expect(page).to have_current_path(novels_path)
    end
  end

  # ---------------------------------------------------------------------------
  # 7 & 8. Bottom nav — DOM presence and navigation
  #
  # The bottom nav is CSS-hidden at desktop widths (display: none) but always
  # present in the DOM on authenticated pages. Tests use visible: :all because
  # Capybara's default visibility filter would reject a display:none element.
  # Navigation tests use find(..., visible: :all) for the same reason.
  # ---------------------------------------------------------------------------
  describe "bottom nav" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "is present in the DOM on authenticated pages" do
      visit root_path
      expect(page).to have_selector("[data-testid='app-bottom-nav']", visible: :all)
    end

    it "is absent on the login page" do
      visit login_path
      expect(page).not_to have_selector("[data-testid='app-bottom-nav']", visible: :all)
    end

    it "contains a Dashboard link" do
      visit root_path
      within :css, "[data-testid='app-bottom-nav']", visible: :all do
        expect(page).to have_link("Dashboard", visible: :all)
      end
    end

    it "contains a Novels link" do
      visit root_path
      within :css, "[data-testid='app-bottom-nav']", visible: :all do
        expect(page).to have_link("Novels", visible: :all)
      end
    end

    it "Dashboard link navigates to the dashboard" do
      visit novels_path
      find("[data-testid='app-bottom-nav']", visible: :all)
        .find("a", text: "Dashboard", visible: :all)
        .click
      expect(page).to have_current_path(root_path)
    end

    it "Novels link navigates to the novel index" do
      visit root_path
      find("[data-testid='app-bottom-nav']", visible: :all)
        .find("a", text: "Novels", visible: :all)
        .click
      expect(page).to have_current_path(novels_path)
    end
  end
end
