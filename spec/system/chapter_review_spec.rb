# spec/system/chapter_review_spec.rb
#
# Chapter Review — compare (split-pane scroll sync) mode
#
# Covers:
#   1. Compare mode is off by default — split panes hidden, single textarea shown
#   2. Toggling KO shows split panes with Korean and English content
#   3. Toggling KO off hides split panes and restores the single textarea
#   4. Korean pane contains the Korean source text
#   5. English pane contains a textarea pre-filled with the translated text
#   6. Editing the English pane textarea and saving persists the change

require "rails_helper"

RSpec.describe "Chapter Review compare mode", type: :system do
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  let(:org)   { create(:organization) }
  let(:team)  { create(:team, organization: org) }
  let(:user)  { create(:user) }
  let(:novel) { create(:novel, organization: org, title: "Test Novel") }

  let(:korean_text) do
    "첫 번째 단락입니다.\n\n두 번째 단락입니다.\n\n세 번째 단락입니다."
  end

  let(:english_text) do
    "This is the first paragraph.\n\nThis is the second paragraph.\n\nThis is the third paragraph."
  end

  let!(:chapter) do
    ch = create(:chapter, novel: novel, number: 1, status: "translated")
    ch.korean_source.attach(
      io: StringIO.new(korean_text),
      filename: "chapter_1_ko.txt",
      content_type: "text/plain"
    )
    ch.translated_output.attach(
      io: StringIO.new(english_text),
      filename: "chapter_1_en.txt",
      content_type: "text/plain"
    )
    ch
  end

  before do
    create(:membership, user: user, team: team)
    create(:novel_team_assignment, novel: novel, team: team)
    sign_in_as(user)
    visit novel_chapter_review_path(novel)
  end

  # ---------------------------------------------------------------------------
  # 1. Compare mode off by default
  # ---------------------------------------------------------------------------
  it "shows the single textarea and hides split panes by default" do
    expect(page).to have_selector("[data-testid='chapter-review-content']", visible: true)
    expect(page).not_to have_selector(".chapter-review__split-panes", visible: true)
  end

  # ---------------------------------------------------------------------------
  # 2. KO toggle reveals split panes
  # ---------------------------------------------------------------------------
  it "shows split panes when KO toggle is clicked" do
    click_button "KO", match: :first
    expect(page).to have_selector(".chapter-review__split-panes", visible: true)
    expect(page).to have_selector(".chapter-review__korean-pane", visible: true)
    expect(page).to have_selector(".chapter-review__english-pane", visible: true)
  end

  # ---------------------------------------------------------------------------
  # 3. KO toggle off hides split panes again
  # ---------------------------------------------------------------------------
  it "hides split panes when KO is toggled off" do
    click_button "KO", match: :first
    click_button "KO", match: :first
    expect(page).not_to have_selector(".chapter-review__split-panes", visible: true)
    expect(page).to have_selector("[data-testid='chapter-review-content']", visible: true)
  end

  # ---------------------------------------------------------------------------
  # 4. Korean pane contains Korean source text
  # ---------------------------------------------------------------------------
  it "renders Korean paragraphs in the Korean pane" do
    click_button "KO", match: :first
    within ".chapter-review__korean-pane" do
      expect(page).to have_text("첫 번째 단락입니다.")
      expect(page).to have_text("두 번째 단락입니다.")
    end
  end

  # ---------------------------------------------------------------------------
  # 5. English pane pre-filled with translated text
  # ---------------------------------------------------------------------------
  it "pre-fills the English pane textarea with the translated text" do
    click_button "KO", match: :first
    within ".chapter-review__english-pane" do
      expect(page).to have_field(type: "textarea", with: /This is the first paragraph/)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Saving in compare mode persists edits
  # ---------------------------------------------------------------------------
  it "saves pane edits when save is triggered" do
    click_button "KO", match: :first

    within ".chapter-review__english-pane" do
      find("textarea").set("Updated translation content.")
    end

    # Ctrl+S save
    find("[data-testid='button-save-chapter']").click
    sleep 0.5

    saved = chapter.reload.translated_output.download.force_encoding("UTF-8")
    expect(saved).to eq("Updated translation content.")
  end
end
