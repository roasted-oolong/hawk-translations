# spec/system/chapter_photo_upload_spec.rb
#
# Photo scan (OCR) chapter upload — the "Photo scan (OCR)" tab on the chapter
# new/upload page. Covers: tab switching, ordered thumbnail rendering,
# reordering via move-up/move-down, and submission.
#
# Driven by Cuprite (JS-capable) so drag/drop + Stimulus wiring is exercised.

require "rails_helper"

RSpec.describe "Chapter photo upload", type: :system do
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  # Two distinct filenames (same underlying JPEG bytes) so thumbnail rows are
  # distinguishable in order-dependent assertions.
  def photo_fixture_path(filename)
    dir = Rails.root.join("tmp", "photo_upload_fixtures")
    FileUtils.mkdir_p(dir)
    path = dir.join(filename).to_s
    FileUtils.cp(Rails.root.join("spec/fixtures/files/cover.jpg"), path)
    @_photo_fixture_paths ||= []
    @_photo_fixture_paths << path
    path
  end

  def pdf_fixture_path(filename)
    dir = Rails.root.join("tmp", "photo_upload_fixtures")
    FileUtils.mkdir_p(dir)
    path = dir.join(filename).to_s
    FileUtils.cp(Rails.root.join("spec/fixtures/files/sample.pdf"), path)
    @_photo_fixture_paths ||= []
    @_photo_fixture_paths << path
    path
  end

  after do
    Array(@_photo_fixture_paths).each { |path| File.delete(path) if File.exist?(path) }
  end

  let(:org)   { create(:organization) }
  let(:novel) { create(:novel, organization: org) }
  let(:user)  { create(:user) }

  before do
    sign_in_as(user)
    visit new_novel_chapter_path(novel)
    click_button "Photo scan (OCR)"
  end

  it "shows the photo drop zone" do
    expect(page).to have_selector("[data-testid='photo-upload-zone']")
  end

  it "submit button is disabled before any photos are selected" do
    expect(page).to have_button("Upload", disabled: true)
  end

  context "after attaching photos" do
    before do
      attach_file "chapter[images][]", [
        photo_fixture_path("page_1.jpg"),
        photo_fixture_path("page_2.jpg")
      ], make_visible: true
    end

    it "shows a thumbnail row per photo in drop order" do
      names = page.all("[data-testid='photo-upload-row']").map(&:text)
      expect(names[0]).to include("page_1.jpg")
      expect(names[1]).to include("page_2.jpg")
    end

    it "remains disabled until a chapter number is entered" do
      expect(page).to have_button("Upload 2 photos", disabled: true)
    end

    context "moving a photo down" do
      before do
        within all("[data-testid='photo-upload-row']").first do
          click_button "↓"
        end
      end

      it "changes the on-screen order" do
        names = page.all("[data-testid='photo-upload-row']").map(&:text)
        expect(names[0]).to include("page_2.jpg")
        expect(names[1]).to include("page_1.jpg")
      end
    end

    context "removing a photo" do
      before do
        within all("[data-testid='photo-upload-row']").first do
          click_button "Remove"
        end
      end

      it "removes the row" do
        expect(page).to have_selector("[data-testid='photo-upload-row']", count: 1)
      end
    end

    context "with a valid chapter number" do
      before { fill_in "Chapter #", with: 4 }

      it "enables the submit button with the photo count" do
        expect(page).to have_button("Upload 2 photos", disabled: false)
      end

      it "creates the chapter and redirects on submit" do
        click_button "Upload 2 photos"

        expect(page).to have_current_path(novel_chapter_path(novel, Chapter.last))
        expect(page).to have_text("Chapter created.")
      end
    end
  end

  context "after attaching a single PDF" do
    before do
      attach_file "chapter[images][]", [ pdf_fixture_path("scan.pdf") ], make_visible: true
    end

    it "shows a PDF badge instead of an image thumbnail" do
      expect(page).to have_selector("[data-testid='photo-upload-pdf-badge']")
      expect(page).to have_no_selector("[data-testid='photo-upload-thumb']")
    end

    context "with a valid chapter number" do
      before { fill_in "Chapter #", with: 4 }

      it "enables the submit button labeled for a PDF" do
        expect(page).to have_button("Upload PDF", disabled: false)
      end

      it "creates the chapter and redirects on submit" do
        click_button "Upload PDF"

        expect(page).to have_current_path(novel_chapter_path(novel, Chapter.last))
        expect(page).to have_text("Chapter created.")
      end
    end
  end

  context "after attaching a PDF alongside a photo" do
    before do
      attach_file "chapter[images][]", [
        pdf_fixture_path("scan.pdf"),
        photo_fixture_path("page_1.jpg")
      ], make_visible: true
      fill_in "Chapter #", with: 4
    end

    it "shows a batch error and keeps the submit button disabled" do
      expect(page).to have_selector("[data-testid='photo-upload-batch-error']", text: /single PDF/)
      expect(page).to have_button("Upload 2 photos", disabled: true)
    end
  end
end
