# spec/system/m19_sidebar_spec.rb
#
# M19 — Sidebar Navigation
#
# Replaces the top nav bar with a two-element app shell:
#   - Fixed left sidebar  (data-testid="app-sidebar")  — primary navigation
#   - Fixed slim topbar   (data-testid="app-topbar")   — breadcrumb, user, sign-out
#
# Covers:
#   1. Sidebar renders on every authenticated page
#   2. Topbar renders on every authenticated page
#   3. Sidebar and topbar absent on the login page
#   4. Sign-out is reachable from the topbar
#   5. Dashboard link in sidebar navigates correctly
#   6. Novels link in sidebar navigates correctly
#   7. Mobile: hamburger button present at narrow viewport
#   8. Mobile: hamburger toggles sidebar open and closed

RSpec.describe "M19 Sidebar Navigation", type: :system do
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  def resize_to_mobile
    page.driver.resize(375, 812)
  end

  def resize_to_desktop
    page.driver.resize(1280, 800)
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
      # Start on novel index so the click is meaningful.
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
  # 7 & 8. Mobile — hamburger button and sidebar toggle
  # ---------------------------------------------------------------------------
  describe "mobile sidebar toggle" do
    let(:user) { create(:user) }

    before do
      sign_in_as(user)
      visit root_path
      resize_to_mobile
    end

    after { resize_to_desktop }

    it "shows a hamburger button at narrow viewport" do
      expect(page).to have_selector("[data-testid='sidebar-hamburger']")
    end

    it "sidebar is not open by default at narrow viewport" do
      expect(page).not_to have_selector("[data-testid='app-sidebar'][data-sidebar-open='true']")
    end

    it "opens the sidebar when the hamburger is clicked" do
      find("[data-testid='sidebar-hamburger']").click
      expect(page).to have_selector("[data-testid='app-sidebar'][data-sidebar-open='true']")
    end

    it "closes the sidebar when the hamburger is clicked a second time" do
      find("[data-testid='sidebar-hamburger']").click
      expect(page).to have_selector("[data-testid='app-sidebar'][data-sidebar-open='true']")

      find("[data-testid='sidebar-hamburger']").click
      expect(page).not_to have_selector("[data-testid='app-sidebar'][data-sidebar-open='true']")
    end

    it "closes the sidebar when clicking outside it" do
      find("[data-testid='sidebar-hamburger']").click
      expect(page).to have_selector("[data-testid='app-sidebar'][data-sidebar-open='true']")

      # Click somewhere in the topbar area — outside the sidebar
      find("[data-testid='app-topbar']").click
      expect(page).not_to have_selector("[data-testid='app-sidebar'][data-sidebar-open='true']")
    end
  end
end
