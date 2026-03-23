# spec/system/m21_cover_art_spec.rb
#
# M21 — Wire Data + Cover Art Upload
#
# Covers:
#   1. Dashboard: cover image renders when attached
#   2. Dashboard: placeholder renders when no cover art attached
#   3. Dashboard: progress bar width reflects chapter completion
#   4. Novel form: cover art file input present
#   5. Novel form (edit): current cover thumbnail shown when attached
#   6. Novel form (edit): remove cover art button purges the image

require "rails_helper"

RSpec.describe "M21 Cover Art", type: :system do
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  # A minimal 1×1 valid JPEG (binary safe for Active Storage)
  def tiny_jpeg
    # 1×1 white JPEG — real enough to pass content-type sniffing
    File.open(Rails.root.join("spec/fixtures/files/cover.jpg"))
  end

  # ---------------------------------------------------------------------------
  # Shared setup
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
  # 1. Dashboard: cover image renders when cover_art is attached
  # ---------------------------------------------------------------------------
  it "renders the cover <img> on the dashboard when cover art is attached" do
    novel.cover_art.attach(
      io: tiny_jpeg,
      filename: "cover.jpg",
      content_type: "image/jpeg"
    )

    visit root_path

    within "[data-testid='novel-card']" do
      expect(page).to have_css("img[alt]")
      expect(page).not_to have_css(".novel-card__cover--placeholder")
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Dashboard: placeholder renders when no cover art attached
  # ---------------------------------------------------------------------------
  it "renders the placeholder when no cover art is attached" do
    visit root_path

    within "[data-testid='novel-card']" do
      expect(page).not_to have_css("img")
      expect(page).to have_selector("[data-testid='novel-card-cover']")
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Dashboard: progress bar width reflects chapter completion
  # ---------------------------------------------------------------------------
  describe "progress bar" do
    it "shows 0% when no chapters exist" do
      visit root_path
      within "[data-testid='novel-card']" do
        fill = find(".novel-card__progress-fill", visible: :all)
        expect(fill["style"]).to include("width: 0%")
      end
    end

    it "reflects the translated/reviewed chapter ratio" do
      create(:chapter, novel: novel, number: 1, status: "translated")
      create(:chapter, novel: novel, number: 2, status: "reviewed")
      create(:chapter, novel: novel, number: 3, status: "untranslated")
      # 2 of 3 done → 66%

      visit root_path
      within "[data-testid='novel-card']" do
        fill = find(".novel-card__progress-fill", visible: :all)
        expect(fill["style"]).to match(/width:\s*66%/)
      end
    end

    it "shows 100% when all chapters are translated or reviewed" do
      create(:chapter, novel: novel, number: 1, status: "translated")
      create(:chapter, novel: novel, number: 2, status: "reviewed")

      visit root_path
      within "[data-testid='novel-card']" do
        fill = find(".novel-card__progress-fill", visible: :all)
        expect(fill["style"]).to include("width: 100%")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Novel form (new): cover art file input present
  # ---------------------------------------------------------------------------
  it "renders the cover art file input on the new novel form" do
    visit new_novel_path
    expect(page).to have_selector("[data-testid='cover-art-upload']")
    expect(page).to have_css("input[type='file'][accept*='image']")
  end

  # ---------------------------------------------------------------------------
  # 5. Novel form (edit): current cover thumbnail shown when attached
  # ---------------------------------------------------------------------------
  it "shows a cover thumbnail on the edit form when cover art is attached" do
    novel.cover_art.attach(
      io: tiny_jpeg,
      filename: "cover.jpg",
      content_type: "image/jpeg"
    )

    visit edit_novel_path(novel)
    expect(page).to have_selector("[data-testid='cover-art-current']")
    within "[data-testid='cover-art-current']" do
      expect(page).to have_css("img")
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Novel form (edit): remove cover art button purges the image
  # ---------------------------------------------------------------------------
  it "removes the cover art when the remove button is clicked" do
    novel.cover_art.attach(
      io: tiny_jpeg,
      filename: "cover.jpg",
      content_type: "image/jpeg"
    )

    visit edit_novel_path(novel)
    expect(page).to have_selector("[data-testid='cover-art-current']")

    click_on "Remove cover art"

    expect(page).to have_current_path(novel_path(novel))
    expect(novel.reload.cover_art).not_to be_attached
  end
end
