# spec/system/novels_forms_spec.rb
#
# M18 — Novel Create/Edit Forms, Empty States, Modal Confirmation
#
# Covers:
#   1. Novel new — form renders with all expected fields
#   2. Novel create — successful submission redirects to novel show
#   3. Novel create — validation errors render inline
#   4. Novel edit — form pre-populates existing values
#   5. Novel update — successful submission redirects to novel show
#   6. Novel edit — directory_name field is absent (read-only on edit)
#   7. Novel index — empty state renders when no novels exist
#   8. Modal confirmation — appears on destructive action trigger
#   9. Modal confirmation — cancel keeps the record intact
#  10. Modal confirmation — confirm deletes the record
#
# Modal interaction note:
#   Native <dialog> elements open in the browser's top layer via showModal().
#   Cuprite can see their content in the page text, but Capybara's `within`
#   scoping does not reliably interact with top-layer elements. We interact
#   with the dialog's buttons directly on the page after confirming the dialog
#   is open, rather than using within scoping.

require "rails_helper"

RSpec.describe "M18 Novel Forms, Empty States & Modal", type: :system do
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  let(:org)  { create(:organization) }
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  # ---------------------------------------------------------------------------
  # 1. Novel new — form structure
  # ---------------------------------------------------------------------------
  describe "novel new form" do
    before { visit new_novel_path }

    it "renders the page title" do
      expect(page).to have_text("New Novel")
    end

    it "renders the breadcrumb" do
      expect(page).to have_selector("[data-testid='breadcrumb']")
    end

    it "renders the form" do
      expect(page).to have_selector("[data-testid='novel-form']")
    end

    it "renders a title field" do
      expect(page).to have_field("Title")
    end

    it "renders a directory_name field" do
      expect(page).to have_field("Directory name")
    end

    it "renders a korean_title field" do
      expect(page).to have_field("Korean title")
    end

    it "renders a genre field" do
      expect(page).to have_field("Genre")
    end

    it "renders a visibility select" do
      expect(page).to have_select("Visibility")
    end

    it "renders a summary textarea" do
      expect(page).to have_field("Summary")
    end

    it "renders a tone textarea" do
      expect(page).to have_field("Tone")
    end

    it "renders a notes textarea" do
      expect(page).to have_field("Notes")
    end

    it "renders a series select" do
      expect(page).to have_select("Series")
    end

    it "renders a point of contact select" do
      expect(page).to have_select("Point of contact")
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Novel create — success
  # ---------------------------------------------------------------------------
  describe "creating a novel" do
    before do
      org # ensure the org exists so the hidden field has a value
      visit new_novel_path
    end

    it "redirects to the novel show page on success" do
      fill_in "Title", with: "Test Novel"
      fill_in "Directory name", with: "test-novel"
      click_button "Save"

      expect(page).to have_current_path(novel_path(Novel.last))
      expect(page).to have_text("Novel created.")
    end

    it "creates a novel record in the database" do
      fill_in "Title", with: "Test Novel"
      fill_in "Directory name", with: "test-novel"
      expect { click_button "Save" }.to change(Novel, :count).by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Novel create — validation errors
  # ---------------------------------------------------------------------------
  describe "novel create with validation errors" do
    before do
      org
      visit new_novel_path
      click_button "Save" # submit with no title, no directory_name
    end

    it "re-renders the new form" do
      expect(page).to have_selector("[data-testid='novel-form']")
    end

    it "shows the error summary block" do
      expect(page).to have_selector("[data-testid='form-errors']")
    end

    it "shows a relevant error message" do
      expect(page).to have_text("Title can't be blank")
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Novel edit — form pre-population
  # ---------------------------------------------------------------------------
  describe "novel edit form" do
    let(:novel) { create(:novel, organization: org, title: "Edit Me", korean_title: "편집") }

    before { visit edit_novel_path(novel) }

    it "renders the page title" do
      expect(page).to have_text("Edit Novel")
    end

    it "renders the breadcrumb" do
      expect(page).to have_selector("[data-testid='breadcrumb']")
    end

    it "pre-populates the title field" do
      expect(page).to have_field("Title", with: "Edit Me")
    end

    it "pre-populates the Korean title field" do
      expect(page).to have_field("Korean title", with: "편집")
    end

    it "does NOT render an editable directory_name field" do
      expect(page).not_to have_field("Directory name")
    end

    it "shows the directory_name as read-only text" do
      expect(page).to have_selector("[data-testid='directory-name-readonly']")
      expect(page).to have_text(novel.directory_name)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Novel update — success
  # ---------------------------------------------------------------------------
  describe "updating a novel" do
    let(:novel) { create(:novel, organization: org, title: "Before") }

    it "redirects to the novel show page and shows the flash" do
      visit edit_novel_path(novel)
      fill_in "Title", with: "After"
      click_button "Save"

      expect(page).to have_current_path(novel_path(novel))
      expect(page).to have_text("Novel updated.")
    end

    it "persists the change" do
      visit edit_novel_path(novel)
      fill_in "Title", with: "After"
      click_button "Save"

      expect(novel.reload.title).to eq("After")
    end

    it "does NOT change the directory_name (field absent from edit form)" do
      original = novel.directory_name
      visit edit_novel_path(novel)
      fill_in "Title", with: "After"
      click_button "Save"

      expect(novel.reload.directory_name).to eq(original)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Novel index empty state
  # ---------------------------------------------------------------------------
  describe "novel index empty state" do
    it "shows the empty state when no novels exist" do
      visit novels_path
      expect(page).to have_selector("[data-testid='novels-empty']")
    end

    it "does not show the empty state when novels exist" do
      create(:novel, organization: org)
      visit novels_path
      expect(page).not_to have_selector("[data-testid='novels-empty']")
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Modal confirmation — novel Remove
  # ---------------------------------------------------------------------------
  describe "modal confirmation dialog" do
    let(:novel) { create(:novel, organization: org, title: "Doomed Novel") }

    before { visit novel_path(novel) }

    it "opens the confirmation dialog when Remove is clicked" do
      click_button "Remove"
      expect(page).to have_selector("[data-testid='modal-dialog'][open]")
    end

    it "shows the confirmation message in the dialog" do
      click_button "Remove"
      # Confirm the dialog is open and the message is visible on the page.
      # We check page-level text rather than scoping into the dialog element
      # because native <dialog> top-layer content is accessible directly.
      expect(page).to have_selector("[data-testid='modal-dialog'][open]")
      expect(page).to have_text("Doomed Novel")
    end

    it "closes the dialog without deleting when Cancel is clicked" do
      click_button "Remove"
      expect(page).to have_selector("[data-testid='modal-dialog'][open]")

      # Click the Cancel button directly — no within scoping needed for top-layer dialog
      find("[data-testid='modal-dialog'] [data-modal-cancel]").click

      expect(page).not_to have_selector("[data-testid='modal-dialog'][open]")
      expect(Novel.exists?(novel.id)).to be true
    end

    it "deletes the record and redirects when Confirm is clicked" do
      click_button "Remove"
      expect(page).to have_selector("[data-testid='modal-dialog'][open]")

      # Click the Confirm button directly — no within scoping needed for top-layer dialog
      find("[data-testid='modal-dialog'] [data-modal-confirm]").click

      expect(page).to have_current_path(novels_path)
      expect(Novel.exists?(novel.id)).to be false
    end
  end
end
