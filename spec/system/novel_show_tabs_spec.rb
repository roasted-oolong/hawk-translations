# spec/system/novel_show_tabs_spec.rb
#
# M23 — Novel Show: Tabbed Layout
#
# Covers:
#   1. Header block — cover art slot, genre badge, title, Korean title,
#      summary, progress bar with label, Edit + Remove actions
#   2. Tab strip — four tabs render; Chapters and Bible are active;
#      Review and Voice Calibration are aria-disabled
#   3. Chapters tab — clicking it activates it and sets a src on the frame
#   4. Bible tab    — clicking it activates it and sets a src on the frame
#   5. Disabled tabs — aria-disabled, not clickable, tooltip present
#   6. Active tab restored from sessionStorage after navigation
#
# Regression (existing novel show structure must not break):
#   7. Old three-section layout (chapter summary, bible summary, jobs link)
#      is no longer rendered.

require "rails_helper"

RSpec.describe "M23 Novel Show Tabbed Layout", type: :system do
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  let(:org)   { create(:organization) }
  let(:user)  { create(:user) }
  let(:novel) do
    create(:novel,
      organization:  org,
      title:         "Idols: Rewind",
      korean_title:  "아이돌: 리와인드",
      genre:         "Romance",
      summary:       "A story about second chances.")
  end

  before { sign_in_as(user) }

  # ---------------------------------------------------------------------------
  # 1. Header block
  # ---------------------------------------------------------------------------
  describe "novel show header block" do
    before { visit novel_path(novel) }

    it "renders the novel title" do
      expect(page).to have_selector("[data-testid='novel-title']")
      expect(page).to have_text("Idols: Rewind")
    end

    it "renders the Korean title" do
      expect(page).to have_text("아이돌: 리와인드")
    end

    it "renders the summary" do
      expect(page).to have_text("A story about second chances.")
    end

    it "renders the genre badge" do
      expect(page).to have_selector("[data-testid='novel-genre-badge']", text: "Romance")
    end

    it "does not render a genre badge when genre is blank" do
      novel.update!(genre: nil)
      visit novel_path(novel)
      expect(page).not_to have_selector("[data-testid='novel-genre-badge']")
    end

    it "renders the progress bar track" do
      expect(page).to have_selector("[data-testid='novel-show-progress-track']")
    end

    it "shows reviewed / total count in the progress label" do
      create(:chapter, novel: novel, status: "reviewed")
      create(:chapter, novel: novel, status: "reviewed")
      create(:chapter, novel: novel, status: "untranslated")
      visit novel_path(novel)

      expect(page).to have_selector("[data-testid='novel-show-progress-label']",
                                    text: "2 / 3")
    end

    it "shows 0 / 0 in the progress label when no chapters exist" do
      expect(page).to have_selector("[data-testid='novel-show-progress-label']",
                                    text: "0 / 0")
    end

    it "renders the Edit link" do
      expect(page).to have_link("Edit")
    end

    it "renders the Remove button" do
      expect(page).to have_button("Remove")
    end

    it "renders the breadcrumb" do
      expect(page).to have_selector("[data-testid='breadcrumb']")
    end

    context "with cover art" do
      before do
        novel.cover_art.attach(
          io:           File.open(Rails.root.join("spec/fixtures/files/cover.jpg")),
          filename:     "cover.jpg",
          content_type: "image/jpeg"
        )
        visit novel_path(novel)
      end

      it "renders the cover image inside the cover slot" do
        expect(page).to have_selector("[data-testid='novel-show-cover'] img")
      end
    end

    context "without cover art" do
      it "renders the cover slot placeholder without an img tag" do
        expect(page).to have_selector("[data-testid='novel-show-cover']")
        expect(page).not_to have_selector("[data-testid='novel-show-cover'] img")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Tab strip — structure
  # ---------------------------------------------------------------------------
  describe "tab strip" do
    before { visit novel_path(novel) }

    it "renders the tab strip container" do
      expect(page).to have_selector("[data-testid='novel-tabs']")
    end

    it "renders a Chapters tab" do
      expect(page).to have_selector("[data-testid='tab-chapters']")
    end

    it "renders a Bible tab" do
      expect(page).to have_selector("[data-testid='tab-bible']")
    end

    it "renders a Review tab" do
      expect(page).to have_selector("[data-testid='tab-review']")
    end

    it "renders a Voice Calibration tab" do
      expect(page).to have_selector("[data-testid='tab-voice-calibration']")
    end

    it "Chapters tab is not aria-disabled" do
      expect(page).not_to have_selector("[data-testid='tab-chapters'][aria-disabled='true']")
    end

    it "Bible tab is not aria-disabled" do
      expect(page).not_to have_selector("[data-testid='tab-bible'][aria-disabled='true']")
    end

    it "Review tab is aria-disabled" do
      expect(page).to have_selector("[data-testid='tab-review'][aria-disabled='true']")
    end

    it "Voice Calibration tab is aria-disabled" do
      expect(page).to have_selector("[data-testid='tab-voice-calibration'][aria-disabled='true']")
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Chapters tab — activation and frame src
  # ---------------------------------------------------------------------------
  describe "Chapters tab" do
    before { visit novel_path(novel) }

    it "is active by default (no prior sessionStorage)" do
      expect(page).to have_selector("[data-testid='tab-chapters'].novel-tab--active")
    end

    it "shows the Chapters tab panel frame" do
      expect(page).to have_selector("turbo-frame[id='tab-panel-chapters']")
    end

    it "panel frame carries a data-testid" do
      expect(page).to have_selector("[data-testid='tab-panel-chapters']")
    end

    it "clicking Chapters tab keeps/restores it as active" do
      # Click Bible first, then switch back to Chapters
      click_on "Bible"
      click_on "Chapters"
      expect(page).to have_selector("[data-testid='tab-chapters'].novel-tab--active")
    end

    it "frame has a src attribute pointing to the chapters path" do
      frame = find("turbo-frame[id='tab-panel-chapters']")
      expect(frame["src"]).to include(novel_chapters_path(novel))
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Bible tab — activation and frame src
  # ---------------------------------------------------------------------------
  describe "Bible tab" do
    before { visit novel_path(novel) }

    it "is not active by default" do
      expect(page).not_to have_selector("[data-testid='tab-bible'].novel-tab--active")
    end

    it "shows the Bible tab panel frame" do
      expect(page).to have_selector("turbo-frame[id='tab-panel-bible']")
    end

    it "clicking Bible tab marks it active" do
      click_on "Bible"
      expect(page).to have_selector("[data-testid='tab-bible'].novel-tab--active")
    end

    it "clicking Bible tab deactivates Chapters" do
      click_on "Bible"
      expect(page).not_to have_selector("[data-testid='tab-chapters'].novel-tab--active")
    end

    it "frame has a src attribute pointing to the bible path" do
      frame = find("turbo-frame[id='tab-panel-bible']")
      expect(frame["src"]).to include(novel_bible_path(novel))
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Disabled tabs — no navigation, tooltip present
  # ---------------------------------------------------------------------------
  describe "disabled tabs" do
    before { visit novel_path(novel) }

    it "Review tab does not navigate when clicked" do
      find("[data-testid='tab-review']").click
      expect(page).to have_current_path(novel_path(novel))
    end

    it "Voice Calibration tab does not navigate when clicked" do
      find("[data-testid='tab-voice-calibration']").click
      expect(page).to have_current_path(novel_path(novel))
    end

    it "Review tab has a coming-soon title tooltip" do
      expect(page).to have_selector("[data-testid='tab-review'][title='Coming soon']")
    end

    it "Voice Calibration tab has a coming-soon title tooltip" do
      expect(page).to have_selector("[data-testid='tab-voice-calibration'][title='Coming soon']")
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Active tab restored from sessionStorage after navigation
  # ---------------------------------------------------------------------------
  describe "tab persistence via sessionStorage" do
    it "defaults to Chapters tab when no sessionStorage entry exists" do
      visit novel_path(novel)
      expect(page).to have_selector("[data-testid='tab-chapters'].novel-tab--active")
    end

    it "restores the Bible tab after navigating away and back" do
      visit novel_path(novel)

      click_on "Bible"
      expect(page).to have_selector("[data-testid='tab-bible'].novel-tab--active")

      visit novels_path
      visit novel_path(novel)

      # tabs_controller reads sessionStorage on connect; Bible must be restored
      expect(page).to have_selector("[data-testid='tab-bible'].novel-tab--active")
    end

    it "does not bleed tab state between different novels" do
      other_novel = create(:novel, organization: org, title: "Other Novel")

      visit novel_path(novel)
      click_on "Bible"

      # Visit a different novel — should default to Chapters, not Bible
      visit novel_path(other_novel)
      expect(page).to have_selector("[data-testid='tab-chapters'].novel-tab--active")
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Regression — old novel show sections are gone
  # ---------------------------------------------------------------------------
  describe "removed sections" do
    before { visit novel_path(novel) }

    it "no longer renders the chapter summary section" do
      expect(page).not_to have_selector("[data-testid='novel-chapters-summary']")
    end

    it "no longer renders the bible summary section" do
      expect(page).not_to have_selector("[data-testid='novel-bible-summary']")
    end

    it "no longer renders a 'View all chapters' link" do
      expect(page).not_to have_link(/View all.*chapters/)
    end

    it "no longer renders a 'Translation Jobs' section link" do
      expect(page).not_to have_link("Translation Jobs")
    end
  end
end
