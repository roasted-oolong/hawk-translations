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
