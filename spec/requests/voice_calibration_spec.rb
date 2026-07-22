require "rails_helper"

RSpec.describe "VoiceCalibration tab", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/voice_calibration" do
    it "returns 200" do
      get novel_voice_calibration_tab_path(novel)
      expect(response).to have_http_status(:ok)
    end

    context "when a voice calibration job is running" do
      before { create(:chapter, novel: novel, number: 70, status: "reviewed") }

      it "shows the running indicator" do
        create(:translation_job, :voice_calibration, :running, novel: novel, user: user,
               chapter_start: 70, chapter_end: 70)

        get novel_voice_calibration_tab_path(novel)

        expect(response.body).to include("Running")
        expect(response.body).not_to include("vc-tab__last-run--failed")
      end
    end

    context "when the last voice calibration job completed" do
      before { create(:chapter, novel: novel, number: 70, status: "reviewed") }

      it "shows the completed indicator" do
        create(:translation_job, :voice_calibration, :completed, novel: novel, user: user,
               chapter_start: 70, chapter_end: 70)

        get novel_voice_calibration_tab_path(novel)

        expect(response.body).to include("Completed")
        expect(response.body).not_to include("vc-tab__last-run--failed")
      end
    end

    context "when the last voice calibration job failed and no completed job exists" do
      before { create(:chapter, novel: novel, number: 70, status: "reviewed") }

      it "shows the failed indicator" do
        create(:translation_job, :voice_calibration, :failed, novel: novel, user: user,
               chapter_start: 70, chapter_end: 70)

        get novel_voice_calibration_tab_path(novel)

        expect(response.body).to include("vc-tab__last-run--failed")
        expect(response.body).to include("Failed")
      end

      it "links to the translation job show page" do
        job = create(:translation_job, :voice_calibration, :failed, novel: novel, user: user,
                     chapter_start: 70, chapter_end: 70)

        get novel_voice_calibration_tab_path(novel)

        expect(response.body).to include(novel_translation_job_path(novel, job))
      end
    end

    context "when both a failed and a completed job exist" do
      before do
        create(:chapter, novel: novel, number: 69, status: "reviewed")
        create(:chapter, novel: novel, number: 70, status: "reviewed")
      end

      it "shows the more recent one when the completed job is newer" do
        create(:translation_job, :voice_calibration, :failed, novel: novel, user: user,
               chapter_start: 69, chapter_end: 69, created_at: 1.hour.ago)
        create(:translation_job, :voice_calibration, :completed, novel: novel, user: user,
               chapter_start: 70, chapter_end: 70)

        get novel_voice_calibration_tab_path(novel)

        expect(response.body).to include("Completed")
        expect(response.body).not_to include("vc-tab__last-run--failed")
      end

      it "shows the more recent one when the failed job is newer" do
        create(:translation_job, :voice_calibration, :completed, novel: novel, user: user,
               chapter_start: 69, chapter_end: 69, created_at: 1.hour.ago)
        job = create(:translation_job, :voice_calibration, :failed, novel: novel, user: user,
                     chapter_start: 70, chapter_end: 70)

        get novel_voice_calibration_tab_path(novel)

        expect(response.body).to include("vc-tab__last-run--failed")
        expect(response.body).to include(novel_translation_job_path(novel, job))
        expect(response.body).not_to include("Last run: Chapter 69")
      end
    end
  end
end
