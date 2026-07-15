# spec/system/m16_chapters_jobs_spec.rb
#
# M16 — Chapter List & Translation Jobs
# M22 — Unified Chapter Upload (upload form section rewritten)
#
# Covers:
#   1. Chapter index — table renders, status badges present, upload + download links
#   2. Chapter new — unified upload form (M22)
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
        expect(page).to have_link("Upload Chapters")
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
  # 2. Chapter new — unified upload form (M22)
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

    it "renders the drop zone" do
      expect(page).to have_selector("[data-testid='upload-zone']")
    end

    it "submit button is disabled before any files are selected" do
      expect(page).to have_button("Upload", disabled: true)
    end

    it "does not show the review table before files are selected" do
      expect(page).not_to have_selector("[data-testid='upload-review-table']")
    end

    context "after attaching a Korean-content file" do
      let(:korean_content) { "가나다라마바사아자차" * 40 }

      before do
        # Attach a file whose content is Hangul-majority → Korean
        file_path = write_upload_fixture("korean_source.txt", korean_content)
        attach_file("chapter[files][]", file_path, make_visible: true)
      end

      it "shows the review table" do
        expect(page).to have_selector("[data-testid='upload-review-table']")
      end

      it "shows a row for the attached file" do
        expect(page).to have_selector("[data-testid='upload-review-row']")
      end

      it "shows a Korean language badge" do
        expect(page).to have_selector("[data-testid='upload-language-badge']", text: "Korean")
      end
    end

    context "after attaching an English-content file" do
      let(:english_content) { "The manager stepped into the boardroom. " * 40 }

      before do
        file_path = write_upload_fixture("english_output.txt", english_content)
        attach_file("chapter[files][]", file_path, make_visible: true)
      end

      it "shows an English language badge" do
        expect(page).to have_selector("[data-testid='upload-language-badge']", text: "English")
      end
    end

    context "chapter number pre-fill from filename" do
      let(:korean_content) { "가나다라마바사아자차" * 40 }

      it "pre-fills the number input when the filename matches a known pattern" do
        file_path = write_upload_fixture("3화.txt", korean_content)
        attach_file("chapter[files][]", file_path, make_visible: true)
        expect(page).to have_field("chapter[numbers][3화.txt]", with: "3")
      end

      it "leaves the number input blank when the filename does not match" do
        file_path = write_upload_fixture("notes.txt", korean_content)
        attach_file("chapter[files][]", file_path, make_visible: true)
        expect(page).to have_field("chapter[numbers][notes.txt]", with: "")
      end
    end

    context "submit button validation" do
      let(:korean_content) { "가나다라마바사아자차" * 40 }

      # The submit button's label/disabled state is updated via JS after an
      # async FileReader read (see upload_review_controller.ts#addFiles).
      # have_selector reliably polls for this; have_button's combined
      # disabled+text filter does not reliably re-check an existing node's
      # value/disabled properties as they change in place, so these assert
      # via a plain CSS attribute selector on the same submit input instead.
      def submit_button_selector(value:, disabled:)
        "[data-testid='upload-submit'][value='#{value}']" + (disabled ? "[disabled]" : ":not([disabled])")
      end

      it "remains disabled while any row has no chapter number" do
        file_path = write_upload_fixture("notes.txt", korean_content)
        attach_file("chapter[files][]", file_path, make_visible: true)

        expect(page).to have_selector(submit_button_selector(value: "Upload 1 file", disabled: true))
      end

      it "enables once all rows have a valid number" do
        file_path = write_upload_fixture("3화.txt", korean_content)
        attach_file("chapter[files][]", file_path, make_visible: true)

        expect(page).to have_selector(submit_button_selector(value: "Upload 1 file", disabled: false))
      end

      it "updates the button label to reflect the file count" do
        attach_file("chapter[files][]", [
          write_upload_fixture("3화.txt", korean_content),
          write_upload_fixture("4화.txt", korean_content)
        ], make_visible: true)

        expect(page).to have_selector(submit_button_selector(value: "Upload 2 files", disabled: false))
      end
    end

    context "remove button" do
      let(:korean_content) { "가나다라마바사아자차" * 40 }

      it "removes the row from the review table" do
        file_path = write_upload_fixture("3화.txt", korean_content)
        attach_file("chapter[files][]", file_path, make_visible: true)
        expect(page).to have_selector("[data-testid='upload-review-row']")

        click_button "Remove"
        expect(page).not_to have_selector("[data-testid='upload-review-row']")
      end

      it "hides the review table after the last row is removed" do
        file_path = write_upload_fixture("3화.txt", korean_content)
        attach_file("chapter[files][]", file_path, make_visible: true)

        click_button "Remove"
        expect(page).not_to have_selector("[data-testid='upload-review-table']")
      end

      it "disables the submit button after all rows are removed" do
        file_path = write_upload_fixture("3화.txt", korean_content)
        attach_file("chapter[files][]", file_path, make_visible: true)

        click_button "Remove"
        expect(page).to have_button("Upload", disabled: true)
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

      it "shows a Cancel button for queued and running jobs (TranslationJob#cancellable?)" do
        expect(page).to have_button("Cancel", count: 2)
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

      it "marks the job cancelled instead of removing it" do
        visit novel_translation_jobs_path(novel)

        # Cancel button opens the shared confirmation modal; complete the
        # modal flow before asserting the outcome. destroy redirects back to
        # this same index (redirect_back), so the row's status badge — not a
        # flash message, which doesn't reliably survive the modal's
        # Turbo-driven submission — is the durable signal cancellation
        # actually happened.
        click_button "Cancel"
        expect(page).to have_selector("[data-testid='modal-dialog'][open]")
        find("[data-testid='modal-dialog'] [data-modal-confirm]").click

        expect(job.reload.status).to eq("cancelled")
        expect(page).to have_selector(".status-badge--cancelled")
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
