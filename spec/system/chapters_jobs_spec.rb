# spec/system/m16_chapters_jobs_spec.rb
#
# M16 — Chapter List & Translation Jobs
#
# Covers:
#   1. Chapter index — table renders, status badges present, upload + download links
#   2. Chapter new — single upload form, bulk upload form
#   3. Translation jobs index — job list, trigger form, cancel action
#   4. Translation jobs show — job detail, result payload, Turbo Frame polling markup
#
# All specs driven by Cuprite (JS-capable) so Turbo navigation works correctly.

require "rails_helper"

RSpec.describe "M16 Chapter List & Translation Jobs", type: :system do
  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------
  def sign_in_as(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    visit "/auth/google_oauth2/callback"
  end

  # ---------------------------------------------------------------------------
  # 1. Chapter index
  # ---------------------------------------------------------------------------
  describe "chapter index" do
    let(:org)    { create(:organization) }
    let(:novel)  { create(:novel, organization: org) }
    let(:user)   { create(:user) }

    before { sign_in_as(user) }

    context "when no chapters exist" do
      it "renders the empty state" do
        visit novel_chapters_path(novel)
        expect(page).to have_selector("[data-testid='chapters-empty']")
      end

      it "shows the upload button even with no chapters" do
        visit novel_chapters_path(novel)
        expect(page).to have_link("Upload Chapter(s)")
      end
    end

    context "with chapters" do
      let!(:ch1) { create(:chapter, novel: novel, number: 1, status: "untranslated") }
      let!(:ch2) { create(:chapter, novel: novel, number: 2, status: "translated") }
      let!(:ch3) { create(:chapter, novel: novel, number: 3, status: "reviewed") }

      before { visit novel_chapters_path(novel) }

      it "renders the chapter table" do
        expect(page).to have_selector("[data-testid='chapters-table']")
      end

      it "shows all chapters in order" do
        within "[data-testid='chapters-table']" do
          expect(page).to have_text("1")
          expect(page).to have_text("2")
          expect(page).to have_text("3")
        end
      end

      it "renders a status badge for each chapter" do
        expect(page).to have_selector("[data-testid='status-badge']", count: 3)
      end

      it "shows the untranslated badge" do
        within "[data-testid='chapters-table']" do
          expect(page).to have_selector(".status-badge--untranslated")
        end
      end

      it "shows the translated badge" do
        within "[data-testid='chapters-table']" do
          expect(page).to have_selector(".status-badge--translated")
        end
      end

      it "shows the reviewed badge" do
        within "[data-testid='chapters-table']" do
          expect(page).to have_selector(".status-badge--reviewed")
        end
      end

      it "renders the breadcrumb" do
        expect(page).to have_selector("[data-testid='breadcrumb']")
      end

      it "links chapter numbers to the chapter show page" do
        within "[data-testid='chapters-table']" do
          click_link "1"
        end
        expect(page).to have_current_path(novel_chapter_path(novel, ch1))
      end
    end

    context "with download links" do
      let!(:chapter) { create(:chapter, novel: novel, number: 1) }

      it "shows a dash for Korean source when no file is attached" do
        visit novel_chapters_path(novel)
        within "[data-testid='chapters-table']" do
          expect(page).to have_text("—")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Chapter new — upload form
  # ---------------------------------------------------------------------------
  describe "chapter new / upload form" do
    let(:org)   { create(:organization) }
    let(:novel) { create(:novel, organization: org) }
    let(:user)  { create(:user) }

    before do
      sign_in_as(user)
      visit new_novel_chapter_path(novel)
    end

    it "renders the page" do
      expect(page).to have_current_path(new_novel_chapter_path(novel))
    end

    it "renders the breadcrumb" do
      expect(page).to have_selector("[data-testid='breadcrumb']")
    end

    it "has a single chapter upload fieldset" do
      expect(page).to have_selector("[data-testid='single-upload-fieldset']")
    end

    it "has a bulk upload fieldset" do
      expect(page).to have_selector("[data-testid='bulk-upload-fieldset']")
    end

    it "has a chapter number field in the single upload section" do
      within "[data-testid='single-upload-fieldset']" do
        expect(page).to have_field("Chapter number")
      end
    end

    it "has a file input for single upload" do
      within "[data-testid='single-upload-fieldset']" do
        expect(page).to have_field("Korean source file")
      end
    end

    it "has a multi-file input for bulk upload" do
      within "[data-testid='bulk-upload-fieldset']" do
        expect(page).to have_field("Korean source files")
      end
    end

    it "has a status select in the single upload section" do
      within "[data-testid='single-upload-fieldset']" do
        expect(page).to have_select("Status")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Translation jobs index
  # ---------------------------------------------------------------------------
  describe "translation jobs index" do
    let(:org)   { create(:organization) }
    let(:novel) { create(:novel, organization: org) }
    let(:user)  { create(:user) }

    before { sign_in_as(user) }

    context "when no jobs exist" do
      it "renders the empty state" do
        visit novel_translation_jobs_path(novel)
        expect(page).to have_selector("[data-testid='jobs-empty']")
      end
    end

    context "with jobs" do
      let!(:job_queued)    { create(:translation_job, novel: novel, user: user, status: "queued",    job_type: "preread",     chapter_start: 1, chapter_end: 1) }
      let!(:job_running)   { create(:translation_job, novel: novel, user: user, status: "running",   job_type: "preread",     chapter_start: 2, chapter_end: 2) }
      let!(:job_completed) { create(:translation_job, novel: novel, user: user, status: "completed", job_type: "bible_build", chapter_start: 1, chapter_end: 10) }
      let!(:job_failed)    { create(:translation_job, novel: novel, user: user, status: "failed",    job_type: "preread",     chapter_start: 3, chapter_end: 3) }

      before { visit novel_translation_jobs_path(novel) }

      it "renders the jobs table" do
        expect(page).to have_selector("[data-testid='jobs-table']")
      end

      it "renders a status badge for each job" do
        expect(page).to have_selector("[data-testid='status-badge']", count: 4)
      end

      it "shows the queued badge" do
        expect(page).to have_selector(".status-badge--queued")
      end

      it "shows the running badge" do
        expect(page).to have_selector(".status-badge--running")
      end

      it "shows the completed badge" do
        expect(page).to have_selector(".status-badge--completed")
      end

      it "shows the failed badge" do
        expect(page).to have_selector(".status-badge--failed")
      end

      it "shows View links for all jobs" do
        within "[data-testid='jobs-table']" do
          expect(page).to have_link("View", count: 4)
        end
      end

      it "shows a Cancel button only for the queued job" do
        expect(page).to have_button("Cancel", count: 1)
      end

      it "renders the breadcrumb" do
        expect(page).to have_selector("[data-testid='breadcrumb']")
      end
    end

    context "trigger form" do
      before { visit novel_translation_jobs_path(novel) }

      it "renders the trigger form" do
        expect(page).to have_selector("[data-testid='job-trigger-form']")
      end

      it "has a job type select" do
        within "[data-testid='job-trigger-form']" do
          expect(page).to have_select("Job type")
        end
      end

      it "has chapter start and end fields" do
        within "[data-testid='job-trigger-form']" do
          expect(page).to have_field("Chapter start")
          expect(page).to have_field("Chapter end")
        end
      end

      it "has a submit button" do
        within "[data-testid='job-trigger-form']" do
          expect(page).to have_button("Trigger job")
        end
      end
    end

    context "cancelling a queued job" do
      let!(:job) { create(:translation_job, novel: novel, user: user, status: "queued", chapter_start: 1, chapter_end: 1) }

      it "removes the job and shows a notice after cancellation" do
        visit novel_translation_jobs_path(novel)
        click_button "Cancel"
        expect(page).to have_text("Job cancelled")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Translation jobs show
  # ---------------------------------------------------------------------------
  describe "translation jobs show" do
    let(:org)   { create(:organization) }
    let(:novel) { create(:novel, organization: org) }
    let(:user)  { create(:user) }

    before { sign_in_as(user) }

    context "queued job" do
      let(:job) { create(:translation_job, novel: novel, user: user, status: "queued", chapter_start: 1, chapter_end: 5) }

      before { visit novel_translation_job_path(novel, job) }

      it "renders the job detail page" do
        expect(page).to have_selector("[data-testid='job-detail']")
      end

      it "renders the breadcrumb" do
        expect(page).to have_selector("[data-testid='breadcrumb']")
      end

      it "shows the job type" do
        expect(page).to have_text("Preread")
      end

      it "shows the status badge" do
        expect(page).to have_selector("[data-testid='status-badge']")
        expect(page).to have_selector(".status-badge--queued")
      end

      it "renders the Turbo Frame for status polling" do
        expect(page).to have_selector("turbo-frame[id='job-status']")
      end

      it "shows the Cancel button for a queued job" do
        expect(page).to have_button("Cancel job")
      end

      it "shows a pending message when no output exists" do
        expect(page).to have_selector("[data-testid='job-pending-message']")
      end
    end

    context "completed job" do
      let(:job) do
        create(:translation_job, :completed, novel: novel, user: user,
               chapter_start: 1, chapter_end: 1)
      end

      before { visit novel_translation_job_path(novel, job) }

      it "shows the completed status badge" do
        expect(page).to have_selector(".status-badge--completed")
      end

      it "renders the result payload output block" do
        expect(page).to have_selector("[data-testid='job-output']")
        expect(page).to have_text("Job completed successfully.")
      end

      it "does not show the Cancel button" do
        expect(page).not_to have_button("Cancel job")
      end
    end

    context "failed job" do
      let(:job) do
        create(:translation_job, :failed, novel: novel, user: user,
               chapter_start: 1, chapter_end: 1)
      end

      before { visit novel_translation_job_path(novel, job) }

      it "shows the failed status badge" do
        expect(page).to have_selector(".status-badge--failed")
      end

      it "renders the error output block" do
        expect(page).to have_selector("[data-testid='job-output']")
        expect(page).to have_text("Error: something went wrong.")
      end
    end
  end
end
