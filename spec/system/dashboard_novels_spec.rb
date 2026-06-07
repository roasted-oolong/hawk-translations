# spec/system/m15_dashboard_novels_spec.rb
#
# M15 — Dashboard, Novel Index & Novel Show
#
# Covers:
#   1. Dashboard shows zero novels when no NovelTeamAssignment exists for the user
#   2. Dashboard shows an assigned novel with chapter progress and pending jobs count
#   3. Novel index renders novel cards
#   4. Novel show renders novel header, chapter summary, bible section link, jobs link
#
# Setup convention:
#   org, team, novel are explicitly wired to the same organization.
#   user is linked via a membership (user → team) and a novel_team_assignment (novel → team).
#   This mirrors the real setup requirement and keeps factory associations explicit.

require "rails_helper"

RSpec.describe "M15 Dashboard, Novel Index & Novel Show", type: :system do
  # ---------------------------------------------------------------------------
  # Shared sign-in helper
  # ---------------------------------------------------------------------------
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  # ---------------------------------------------------------------------------
  # 1. Dashboard — no assignment
  # ---------------------------------------------------------------------------
  describe "dashboard with no novel assignment" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "loads successfully" do
      visit root_path
      expect(page).to have_http_status(:ok)
    end

    it "shows the dashboard heading" do
      visit root_path
      expect(page).to have_selector("[data-testid='dashboard-heading']")
    end

    it "shows the empty state when the user has no assigned novels" do
      visit root_path
      expect(page).to have_selector("[data-testid='dashboard-empty']")
    end

    it "does not render any novel cards" do
      create(:novel) # exists in the system but not assigned to this user
      visit root_path
      expect(page).not_to have_selector("[data-testid='novel-card']")
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Dashboard — with assignment
  # ---------------------------------------------------------------------------
  describe "dashboard with an assigned novel" do
    let(:org)   { create(:organization) }
    let(:team)  { create(:team, organization: org) }
    let(:novel) { create(:novel, organization: org, title: "Idols: Rewind") }
    let(:user)  { create(:user) }

    before do
      create(:membership, user: user, team: team)
      create(:novel_team_assignment, novel: novel, team: team)
      sign_in_as(user)
      visit root_path
    end

    it "renders a novel card for the assigned novel" do
      expect(page).to have_selector("[data-testid='novel-card']")
    end

    it "shows the novel title in the card" do
      within "[data-testid='novel-card']" do
        expect(page).to have_text("Idols: Rewind")
      end
    end

    it "shows chapter progress in the card" do
      create(:chapter, novel: novel, status: "translated")
      create(:chapter, novel: novel, status: "untranslated")
      visit root_path

      within "[data-testid='novel-card']" do
        expect(page).to have_text("1") # translated count
        expect(page).to have_text("2") # total count
      end
    end

    it "shows the pending jobs count in the card" do
      create(:translation_job, novel: novel, user: user, status: "queued")
      create(:translation_job, novel: novel, user: user, status: "running")
      visit root_path

      within "[data-testid='novel-card']" do
        expect(page).to have_text("2") # 2 pending (queued + running)
      end
    end

    it "links the card to the novel show page" do
      within "[data-testid='novel-card']" do
        click_link "Idols: Rewind"
      end
      expect(page).to have_current_path(novel_path(novel))
    end

    it "does not show the empty state" do
      expect(page).not_to have_selector("[data-testid='dashboard-empty']")
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Novel index
  # ---------------------------------------------------------------------------
  describe "novel index" do
    let(:org)    { create(:organization) }
    let(:user)   { create(:user) }
    let!(:novel) { create(:novel, organization: org, title: "Test Novel", korean_title: "테스트") }

    before { sign_in_as(user) }

    it "renders the novel index page" do
      visit novels_path
      expect(page).to have_selector("[data-testid='novels-index']")
    end

    it "renders a novel card for each novel" do
      visit novels_path
      expect(page).to have_selector("[data-testid='novel-card']")
    end

    it "shows the novel title" do
      visit novels_path
      expect(page).to have_text("Test Novel")
    end

    it "shows the Korean title" do
      visit novels_path
      expect(page).to have_text("테스트")
    end

    it "shows the empty state when no novels exist" do
      novel.destroy
      visit novels_path
      expect(page).to have_selector("[data-testid='novels-empty']")
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Novel show
  # ---------------------------------------------------------------------------
  describe "novel show" do
    let(:org)   { create(:organization) }
    let(:novel) { create(:novel, organization: org, title: "Idols: Rewind", korean_title: "아이돌: 리와인드") }
    let(:user)  { create(:user) }

    before do
      sign_in_as(user)
      visit novel_path(novel)
    end

    it "renders the novel title" do
      expect(page).to have_selector("[data-testid='novel-title']")
      expect(page).to have_text("Idols: Rewind")
    end

    it "renders the Korean title" do
      expect(page).to have_text("아이돌: 리와인드")
    end

    it "renders the breadcrumb" do
      expect(page).to have_selector("[data-testid='breadcrumb']")
    end

    it "renders the tab strip" do
      expect(page).to have_selector("[data-testid='novel-tabs']")
    end

    it "renders the Chapters tab" do
      expect(page).to have_selector("[data-testid='tab-chapters']")
    end

    it "renders the Bible tab" do
      expect(page).to have_selector("[data-testid='tab-bible']")
    end

    it "renders the progress bar" do
      create(:chapter, novel: novel, status: "reviewed")
      create(:chapter, novel: novel, status: "untranslated")
      visit novel_path(novel)

      expect(page).to have_selector("[data-testid='novel-show-progress-track']")
      expect(page).to have_selector("[data-testid='novel-show-progress-label']")
    end
  end
end
