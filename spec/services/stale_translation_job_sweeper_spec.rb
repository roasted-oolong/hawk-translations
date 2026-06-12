require "rails_helper"

RSpec.describe StaleTranslationJobSweeper do
  let(:novel) { create(:novel) }
  let(:user)  { create(:user) }

  def sq_job(failed: false, finished: false, claimed: false)
    double(
      "SolidQueue::Job",
      failed_execution:  failed ? double("FailedExecution") : nil,
      finished_at:       finished ? Time.current : nil,
      claimed_execution: claimed ? double("ClaimedExecution") : nil
    )
  end

  def stub_sq_lookup(translation_job, sq_job_or_nil)
    allow(SolidQueue::Job).to receive(:find_by)
      .with(id: translation_job.solid_queue_job_id)
      .and_return(sq_job_or_nil)
  end

  describe ".call" do
    context "running job whose Solid Queue execution failed (e.g. pruned worker)" do
      it "marks the job failed with an explanatory payload" do
        job = create(:translation_job, :running, novel: novel, user: user,
                     solid_queue_job_id: "627")
        stub_sq_lookup(job, sq_job(failed: true))

        described_class.call

        expect(job.reload.status).to eq("failed")
        expect(job.result_payload).to include("worker")
      end
    end

    context "running job whose Solid Queue record no longer exists" do
      it "marks the job failed" do
        job = create(:translation_job, :running, novel: novel, user: user,
                     solid_queue_job_id: "999")
        stub_sq_lookup(job, nil)

        described_class.call

        expect(job.reload.status).to eq("failed")
      end
    end

    context "running job whose Solid Queue job finished without updating status" do
      it "marks the job failed" do
        job = create(:translation_job, :running, novel: novel, user: user,
                     solid_queue_job_id: "628")
        stub_sq_lookup(job, sq_job(finished: true))

        described_class.call

        expect(job.reload.status).to eq("failed")
      end
    end

    context "running job currently claimed by a live worker" do
      it "leaves the job untouched" do
        job = create(:translation_job, :running, novel: novel, user: user,
                     solid_queue_job_id: "630")
        stub_sq_lookup(job, sq_job(claimed: true))

        described_class.call

        expect(job.reload.status).to eq("running")
      end
    end

    context "queued job still waiting in the queue (ready, not failed)" do
      it "leaves the job untouched" do
        job = create(:translation_job, :queued, novel: novel, user: user,
                     solid_queue_job_id: "631")
        stub_sq_lookup(job, sq_job)

        described_class.call

        expect(job.reload.status).to eq("queued")
      end
    end

    context "job with no recorded solid_queue_job_id" do
      it "is skipped — liveness cannot be verified" do
        job = create(:translation_job, :running, novel: novel, user: user,
                     solid_queue_job_id: nil)

        expect(SolidQueue::Job).not_to receive(:find_by)
        described_class.call

        expect(job.reload.status).to eq("running")
      end
    end

    context "terminal jobs" do
      it "ignores completed, failed and cancelled jobs" do
        create(:translation_job, :completed, novel: novel, user: user,
               solid_queue_job_id: "1")
        create(:translation_job, :failed, novel: novel, user: user,
               solid_queue_job_id: "2")
        create(:translation_job, novel: novel, user: user, status: "cancelled",
               solid_queue_job_id: "3")

        expect(SolidQueue::Job).not_to receive(:find_by)
        described_class.call
      end
    end

    context "dead preread job with chapters stuck in prereading" do
      it "resets those chapters to preread_failed" do
        create(:chapter, novel: novel, number: 1, status: "prereading")
        job = create(:translation_job, :running, novel: novel, user: user,
                     job_type: "preread", chapter_start: 1, chapter_end: 1,
                     solid_queue_job_id: "632")
        stub_sq_lookup(job, sq_job(failed: true))

        described_class.call

        expect(novel.chapters.find_by(number: 1).status).to eq("preread_failed")
      end
    end
  end
end
