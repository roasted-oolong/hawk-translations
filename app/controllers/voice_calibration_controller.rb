class VoiceCalibrationController < ApplicationController
  before_action :set_novel

  def tab
    @passages           = @novel.voice_calibration_passages.ordered
    @active_job         = @novel.translation_jobs.voice_calibration
                                .where(status: %w[queued running])
                                .order(created_at: :desc).first
    @last_completed_job = @novel.translation_jobs.voice_calibration.completed
                                .where("result_payload IS NOT NULL")
                                .order(created_at: :desc).first
    @last_failed_job    = @novel.translation_jobs.voice_calibration.failed
                                .order(created_at: :desc).first
    # Whichever of the two actually happened most recently — not always the
    # completed one. A newer failure must not be hidden behind an older
    # success (see docs/DECISIONS.md, 2026-07-21).
    @last_finished_job  = [ @last_completed_job, @last_failed_job ].compact.max_by(&:created_at)
    @pending_cards      = pending_card_count(@last_completed_job)
    @reviewed_chapters  = @novel.chapters.reviewed.by_number
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def pending_card_count(job)
    return 0 unless job
    payload = JSON.parse(job.result_payload) rescue {}
    cards   = payload["cards"] || []
    cards.count { |c| c["decision"].nil? }
  end
end
