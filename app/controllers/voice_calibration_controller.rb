class VoiceCalibrationController < ApplicationController
  before_action :set_novel

  def tab
    @passages       = @novel.voice_calibration_passages.ordered
    @pending_job    = @novel.translation_jobs.voice_calibration.completed
                            .where("result_payload IS NOT NULL").order(created_at: :desc).first
    @pending_cards  = pending_card_count(@pending_job)
    @translated_chapters = @novel.chapters.translated.by_number
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
