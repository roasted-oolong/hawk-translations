require "rails_helper"

RSpec.describe "TranslationJobs", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }

  before { sign_in(user) }

  # ---------------------------------------------------------------------------
  # Job list (story #25)
  # ---------------------------------------------------------------------------
  describe "GET /novels/:novel_id/translation_jobs" do
    it "returns 200 and lists jobs for the novel" do
      create(:translation_job, novel: novel, user: user, status: "queued")
      create(:translation_job, novel: novel, user: user, status: "completed")

      get novel_translation_jobs_path(novel)

      expect(response).to have_http_status(:ok)
    end

    it "does not show jobs from other novels" do
      other_novel = create(:novel)
      create(:translation_job, novel: other_novel, user: user)

      get novel_translation_jobs_path(novel)

      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Job show — output / error (story #26)
  # ---------------------------------------------------------------------------
  describe "GET /novels/:novel_id/translation_jobs/:id" do
    it "returns 200 and shows job detail" do
      job = create(:translation_job, :completed, novel: novel, user: user,
                   result_payload: "All done.")

      get novel_translation_job_path(novel, job)

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a job belonging to a different novel" do
      other_novel = create(:novel)
      job = create(:translation_job, novel: other_novel, user: user)

      get novel_translation_job_path(novel, job)

      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # Trigger a job (stories #22, #23, #24)
  # ---------------------------------------------------------------------------
  describe "POST /novels/:novel_id/translation_jobs" do
    context "preread job with a chapter range" do
      it "creates a TranslationJob record and enqueues a background job" do
        expect {
          post novel_translation_jobs_path(novel), params: {
            translation_job: {
              job_type:      "preread",
              chapter_start: "1",
              chapter_end:   "10"
            }
          }
        }.to change(TranslationJob, :count).by(1)
          .and have_enqueued_job(PipelineJob)

        job = TranslationJob.last
        expect(job.preread?).to be true
        expect(job.chapter_start).to eq(1)
        expect(job.chapter_end).to eq(10)
        expect(job.queued?).to be true
        expect(job.user).to eq(user)
        expect(job.novel).to eq(novel)

        expect(response).to redirect_to(novel_translation_jobs_path(novel))
      end
    end

    context "bible_build job (no chapter range)" do
      it "creates a TranslationJob record with nil chapter range" do
        expect {
          post novel_translation_jobs_path(novel), params: {
            translation_job: {
              job_type:      "bible_build",
              chapter_start: "",
              chapter_end:   ""
            }
          }
        }.to change(TranslationJob, :count).by(1)
          .and have_enqueued_job(PipelineJob)

        job = TranslationJob.last
        expect(job.bible_build?).to be true
        expect(job.chapter_start).to be_nil
        expect(job.chapter_end).to be_nil
      end
    end

    context "post_translation_review job (single chapter)" do
      it "creates a TranslationJob with start == end" do
        expect {
          post novel_translation_jobs_path(novel), params: {
            translation_job: {
              job_type:      "post_translation_review",
              chapter_start: "5",
              chapter_end:   "5"
            }
          }
        }.to change(TranslationJob, :count).by(1)
          .and have_enqueued_job(PipelineJob)

        job = TranslationJob.last
        expect(job.post_translation_review?).to be true
        expect(job.chapter_start).to eq(5)
        expect(job.chapter_end).to eq(5)
      end
    end

    context "with invalid params" do
      it "does not create a job when chapter_start > chapter_end" do
        expect {
          post novel_translation_jobs_path(novel), params: {
            translation_job: {
              job_type:      "preread",
              chapter_start: "10",
              chapter_end:   "1"
            }
          }
        }.not_to change(TranslationJob, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not create a job when job_type is missing" do
        expect {
          post novel_translation_jobs_path(novel), params: {
            translation_job: {
              job_type:      "",
              chapter_start: "1",
              chapter_end:   "5"
            }
          }
        }.not_to change(TranslationJob, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel a queued job (story #27)
  # ---------------------------------------------------------------------------
  describe "DELETE /novels/:novel_id/translation_jobs/:id" do
    context "when the job is queued" do
      it "destroys the job record and redirects to job list" do
        job = create(:translation_job, :queued, novel: novel, user: user)

        expect {
          delete novel_translation_job_path(novel, job)
        }.to change(TranslationJob, :count).by(-1)

        expect(response).to redirect_to(novel_translation_jobs_path(novel))
      end
    end

    context "when the job is already running" do
      it "does not destroy the job and redirects with an alert" do
        job = create(:translation_job, :running, novel: novel, user: user)

        expect {
          delete novel_translation_job_path(novel, job)
        }.not_to change(TranslationJob, :count)

        expect(response).to redirect_to(novel_translation_job_path(novel, job))
      end
    end

    context "when the job belongs to a different novel" do
      it "returns 404" do
        other_novel = create(:novel)
        job = create(:translation_job, novel: other_novel, user: user)

        delete novel_translation_job_path(novel, job)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
