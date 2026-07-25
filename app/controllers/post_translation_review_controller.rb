require "digest"

# ---------------------------------------------------------------------------
# PostTranslationReviewController
#
# show/update/commit, structurally parallel to VoiceCalibrationReviewController
# — named by job type (post_translation_review), not domain (not
# BibleReviewController), so its generic show/update mechanics could later
# be lifted into a shared reviewable-job layer without a rename. See
# docs/RAILS_REFACTOR_PLAN.md's R5 section.
#
# Unlike voice_calibration's Stimulus-driven slideshow review, this is a
# plain server-rendered page: each card has Accept/Skip buttons that PATCH
# and redirect back, and a single commit form. Functionally complete, not
# visually polished — the mechanics (decision persistence, staleness
# warning, per-card writer delegation) are what R5's acceptance criteria
# actually require.
# ---------------------------------------------------------------------------
class PostTranslationReviewController < ApplicationController
  before_action :set_novel

  def show
    @job = latest_job
    unless @job
      redirect_to novel_path(@novel), notice: "No completed post-translation review job found."
      return
    end

    payload         = JSON.parse(@job.result_payload) rescue {}
    @cards          = payload["cards"] || []
    @bible_revision = payload["bible_revision"] || {}

    if @cards.empty?
      redirect_to novel_path(@novel), notice: "No bible review cards to review."
      return
    end

    @stale_sections = staleness_warnings(@bible_revision)

    render layout: "review"
  end

  def update
    job = latest_job
    unless job
      redirect_to novel_path(@novel), alert: "No post-translation review job found."
      return
    end

    payload = JSON.parse(job.result_payload) rescue {}
    cards   = payload["cards"] || []
    card    = cards.find { |c| c["id"] == params[:card_id] }
    unless card
      redirect_to novel_post_translation_review_path(@novel), alert: "Card not found."
      return
    end

    decision = params[:decision]
    unless decision.in?(%w[accepted accepted_revised skipped])
      redirect_to novel_post_translation_review_path(@novel), alert: "Invalid decision."
      return
    end

    card["decision"] = decision
    payload["cards"] = cards
    job.update!(result_payload: payload.to_json)

    redirect_to novel_post_translation_review_path(@novel), notice: "Decision recorded."
  end

  def commit
    job = latest_job
    unless job
      redirect_to novel_path(@novel), alert: "No post-translation review job found."
      return
    end

    payload = JSON.parse(job.result_payload) rescue {}
    cards   = payload["cards"] || []
    writer  = Pipeline::BibleReviewWriter.new(novel_dir)

    cards.each do |card|
      next unless card["decision"].in?(%w[accepted accepted_revised])
      card["outcome"] = writer.commit(card).to_s
    end

    payload["cards"] = cards
    job.update!(result_payload: payload.to_json)

    redirect_to novel_path(@novel), notice: "Bible review applied."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def latest_job
    @novel.translation_jobs.post_translation_review.completed
          .where("result_payload IS NOT NULL").order(created_at: :desc).first
  end

  def novel_dir
    File.join(ENV.fetch("HAWK_PROJECT_ROOT"), @novel.directory_name)
  end

  # Compares each bible file's current SHA-256 against the fingerprint
  # captured at proposal-generation time (Pipeline::Ruby::PostTranslationReview).
  # Advisory only — the enforcing check lives in Pipeline::BibleFileEditor's
  # own fresh-read-under-lock at commit time; this is purely so the reviewer
  # sees the warning before deciding, not a guarantee by itself.
  def staleness_warnings(bible_revision)
    bible_revision.filter_map do |section_key, recorded_sha|
      relative = Pipeline::Ruby::PostTranslationReview::BIBLE_FILES[section_key]
      next unless relative

      path    = File.join(novel_dir, relative)
      # Mirrors Pipeline::Ruby::PostTranslationReview's own read_file — a
      # missing bible file reads as "", the same as an empty one, so its
      # fingerprint is Digest::SHA256.hexdigest("") rather than "no hash" —
      # otherwise every never-yet-created bible file would look stale.
      content = File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
      current = Digest::SHA256.hexdigest(content)
      section_key if current != recorded_sha
    end
  end
end
