# spec/system/m20_novel_card_spec.rb
#
# M20 — Novel Card Layout Shell
#
# Gallery-style card rewrite: cover placeholder, serif title, Korean title,
# metadata row, progress bar (static width: 0%), chapter count stat, pending
# jobs badge. No real cover image — Active Storage wired at M21.
#
# Covers:
#   1. Dashboard: novel card renders with cover placeholder
#   2. Dashboard: cover image link navigates to the novel
#   3. Dashboard: novel title link navigates to the novel
#   4. Novel index: novel card renders with cover placeholder
#   5. Novel index: cover image link navigates to the novel
#   6. Novel card: progress bar element is present in the DOM
#   7. Novel card: Korean title renders when present
#   8. Novel card: Korean title absent when nil
#   9. Novel card: pending jobs badge renders when jobs > 0
#  10. Novel card: pending jobs badge absent when no pending jobs

require "rails_helper"

RSpec.describe "M20 Novel Card Layout Shell", type: :system do
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  # ---------------------------------------------------------------------------
  # Shared setup: org → team → user → novel assignment
  # ---------------------------------------------------------------------------
  let(:org)   { create(:organization) }
  let(:team)  { create(:team, organization: org) }
  let(:user)  { create(:user) }
  let(:novel) { create(:novel, organization: org, title: "Idols: Rewind") }

  before do
    create(:membership, user: user, team: team)
    create(:novel_team_assignment, novel: novel, team: team)
    sign_in_as(user)
  end

  # ---------------------------------------------------------------------------
  # 1. Dashboard: card renders with cover placeholder
  # ---------------------------------------------------------------------------
  describe "dashboard novel card" do
    before { visit root_path }

    it "renders a novel card" do
      expect(page).to have_selector("[data-testid='novel-card']")
    end

    it "renders the cover placeholder block" do
      within "[data-testid='novel-card']" do
        expect(page).to have_selector("[data-testid='novel-card-cover']")
      end
    end

    # 2. Cover image link navigates to the novel
    it "cover area links to the novel show page" do
      within "[data-testid='novel-card']" do
        cover_link = find("[data-testid='novel-card-cover-link']")
        expect(cover_link["href"]).to end_with(novel_path(novel))
      end
    end

    # 3. Title link navigates to the novel
    it "title links to the novel show page" do
      within "[data-testid='novel-card']" do
        click_link "Idols: Rewind"
      end
      expect(page).to have_current_path(novel_path(novel))
    end
  end

  # ---------------------------------------------------------------------------
  # 4 & 5. Novel index: card renders + cover link navigates
  # ---------------------------------------------------------------------------
  describe "novel index novel card" do
    before { visit novels_path }

    it "renders a novel card" do
      expect(page).to have_selector("[data-testid='novel-card']")
    end

    it "renders the cover placeholder block" do
      within "[data-testid='novel-card']" do
        expect(page).to have_selector("[data-testid='novel-card-cover']")
      end
    end

    it "cover area links to the novel show page" do
      within "[data-testid='novel-card']" do
        cover_link = find("[data-testid='novel-card-cover-link']")
        expect(cover_link["href"]).to end_with(novel_path(novel))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Progress bar is present in the DOM
  # ---------------------------------------------------------------------------
  describe "progress bar" do
    it "renders the progress track and fill elements" do
      visit root_path
      within "[data-testid='novel-card']" do
        expect(page).to have_selector("[data-testid='novel-card-progress']")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 7 & 8. Korean title conditional rendering
  # ---------------------------------------------------------------------------
  describe "Korean title" do
    it "renders the Korean title when present" do
      novel.update!(korean_title: "아이돌: 리와인드")
      visit root_path
      within "[data-testid='novel-card']" do
        expect(page).to have_selector("[data-testid='novel-card-korean-title']")
        expect(page).to have_text("아이돌: 리와인드")
      end
    end

    it "does not render the Korean title element when nil" do
      novel.update!(korean_title: nil)
      visit root_path
      within "[data-testid='novel-card']" do
        expect(page).not_to have_selector("[data-testid='novel-card-korean-title']")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 9 & 10. Pending jobs badge
  # ---------------------------------------------------------------------------
  describe "pending jobs badge" do
    it "renders the pending jobs badge when queued or running jobs exist" do
      create(:translation_job, novel: novel, user: user, status: "queued")
      create(:translation_job, novel: novel, user: user, status: "running")
      visit root_path
      within "[data-testid='novel-card']" do
        expect(page).to have_selector("[data-testid='novel-card-jobs-badge']")
        expect(page).to have_text("2")
      end
    end

    it "does not render the pending jobs badge when no pending jobs exist" do
      create(:translation_job, novel: novel, user: user, status: "completed")
      visit root_path
      within "[data-testid='novel-card']" do
        expect(page).not_to have_selector("[data-testid='novel-card-jobs-badge']")
      end
    end
  end
end
