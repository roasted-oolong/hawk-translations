class VoiceCalibrationReviewController < ApplicationController
  before_action :set_novel

  def show
    @job     = @novel.translation_jobs.voice_calibration.completed
                     .where("result_payload IS NOT NULL").order(created_at: :desc).first
    @passages = @novel.voice_calibration_passages.ordered

    unless @job
      redirect_to novel_path(@novel), notice: "No completed voice calibration job found."
      return
    end

    payload = JSON.parse(@job.result_payload) rescue {}
    @cards  = payload["cards"] || []

    if @cards.empty?
      redirect_to novel_path(@novel), notice: "No calibration cards to review."
      return
    end

    render layout: "review"
  end

  def update
    job     = @novel.translation_jobs.voice_calibration.completed
                    .where("result_payload IS NOT NULL").order(created_at: :desc).first
    head :not_found and return unless job

    payload  = JSON.parse(job.result_payload) rescue {}
    cards    = payload["cards"] || []
    card     = cards.find { |c| c["id"] == params[:card_id] }
    head :not_found and return unless card

    decision = params.require(:decision)
    unless decision.in?(%w[accepted accepted_revised skipped])
      render json: { error: "Invalid decision" }, status: :unprocessable_entity
      return
    end

    if decision.in?(%w[accepted accepted_revised])
      apply_card!(card, decision)
    end

    card["decision"] = decision
    payload["cards"] = cards
    job.update!(result_payload: payload.to_json)

    render json: { ok: true }
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def apply_card!(card, decision)
    case card["card_type"]
    when "new_pattern"
      rule_text = params[:rule].presence || card["rule"]
      existing  = @novel.voice_calibration_passages.find_by(heading: card["heading"])
      if existing
        existing.update!(rule: rule_text)
      else
        max_pos = @novel.voice_calibration_passages.maximum(:position) || -1
        @novel.voice_calibration_passages.create!(
          heading:               card["heading"],
          chapter_ref:           card["chapter_ref"],
          quote:                 card["quote"],
          what_it_demonstrates:  card["what_it_demonstrates"],
          wrong_version:         card["wrong_version"],
          rule:                  rule_text,
          position:              max_pos + 1
        )
      end
    when "retirement"
      passage_id = card["passage_id"]
      @novel.voice_calibration_passages.find_by(id: passage_id)&.destroy
    end
  end
end
