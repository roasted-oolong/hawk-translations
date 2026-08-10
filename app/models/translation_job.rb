class TranslationJob < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :novel
  belongs_to :user

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enum :job_type, {
    preread:                  "preread",
    translate_batch:          "translate_batch",
    bible_build:              "bible_build",
    post_translation_review:  "post_translation_review",
    voice_calibration:        "voice_calibration",
    chapter_qa:               "chapter_qa"
  }

  enum :status, {
    queued:    "queued",
    running:   "running",
    completed: "completed",
    failed:    "failed",
    cancelled: "cancelled"
  }

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :job_type, presence: true
  validates :status,   presence: true

  validate :chapter_range_valid
  validate :voice_calibration_chapter_reviewed, if: -> { voice_calibration? && chapter_start.present? }
  validate :chapter_qa_single_chapter_translated, if: -> { chapter_qa? && chapter_start.present? }
  validate :chapter_bible_proposals_resolved, if: -> { translate_batch? && chapter_start.present? }

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  scope :recent,     -> { order(created_at: :desc) }
  scope :for_novel,  ->(novel) { where(novel: novel) }
  scope :cancellable, -> { where(status: %w[queued running]) }

  # ---------------------------------------------------------------------------
  # Broadcasts
  # ---------------------------------------------------------------------------
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  # Returns a human-readable label for the chapter range, or nil when no
  # chapter range is set (e.g. bible_build jobs).
  def chapter_range_label
    return nil if chapter_start.nil? && chapter_end.nil?

    if chapter_start == chapter_end
      "Chapter #{chapter_start}"
    else
      "Chapters #{chapter_start}\u2013#{chapter_end}"
    end
  end

  def cancellable?
    queued? || running?
  end

  # translate_batch's result_payload is a JSON blob (per-chapter step data,
  # see Pipeline::Ruby::TranslateBatch) rather than the plain human-readable
  # text every other job type stores — views that render result_payload
  # verbatim should use this instead so a reader sees the human summary, not
  # raw JSON. Falls back to the raw string for any payload that isn't the
  # expected shape (e.g. a failed job's payload, which appends stderr text
  # after the JSON — see PipelineJob's failure branch).
  def result_summary
    return result_payload unless translate_batch?

    JSON.parse(result_payload.to_s)["summary"] || result_payload
  rescue JSON::ParserError
    result_payload
  end

  def shows_progress?
    false
  end

  def cancel!
    transaction do
      update!(status: :cancelled)
      reset_prereading_chapters!
    end
  end

  # Marks a job failed when its worker died out-of-process (e.g. the Solid
  # Queue process was killed and pruned), so PipelineJob's rescue never ran.
  def mark_dead!(reason)
    transaction do
      update!(status: :failed, result_payload: reason)
      reset_prereading_chapters!
    end
  end

  private

  def reset_prereading_chapters!
    return unless preread?

    novel.chapters
      .where(number: chapter_start..chapter_end, status: "prereading")
      .update_all(status: "preread_failed")
  end

  # ---------------------------------------------------------------------------
  # Validation: chapter range consistency
  #
  # Rules:
  #   - Both present is always required — all job types (including bible_build)
  #     must specify a chapter range.
  #   - Both present is valid when start <= end and start >= 1.
  #   - One present and the other nil is always invalid.
  #   - Both nil is always invalid.
  #   - start > end is invalid.
  #   - start < 1 is invalid.
  # ---------------------------------------------------------------------------
  def chapter_range_valid
    start_nil = chapter_start.nil?
    end_nil   = chapter_end.nil?

    # Both nil — invalid for all job types.
    if start_nil && end_nil
      errors.add(:chapter_start, "must be present")
      errors.add(:chapter_end, "must be present")
      return
    end

    # One nil, one present — always invalid.
    if start_nil
      errors.add(:chapter_start, "must be present when chapter_end is set")
      return
    end

    if end_nil
      errors.add(:chapter_end, "must be present when chapter_start is set")
      return
    end

    # Both present — validate range sanity.
    if chapter_start < 1
      errors.add(:chapter_start, "must be a positive integer (>= 1)")
    end

    if chapter_start > chapter_end
      errors.add(:chapter_start, "must be less than or equal to chapter_end")
    end
  end

  def voice_calibration_chapter_reviewed
    unless novel.chapters.reviewed.exists?(number: chapter_start)
      errors.add(:chapter_start, "must be a reviewed chapter")
    end
  end

  # Blocks translate_batch while any chapter in *this job's own* range has
  # an unresolved bible_entry_proposal — checked against the translate
  # job's range, not whatever range the preread job that produced the
  # proposals used. Chapter 77 being fully reviewed doesn't unlock chapter
  # 76: each chapter's proposals are its own gate. See
  # docs/PREREAD_STAGING_DESIGN.md, Part 2.
  def chapter_bible_proposals_resolved
    unresolved = novel.chapters
                       .where(number: chapter_start..chapter_end)
                       .joins(:bible_entry_proposals)
                       .distinct
    if unresolved.exists?
      errors.add(:chapter_start, "has unresolved bible proposals — resolve them at /preread_review first")
    end
  end

  # chapter_qa reviews one already-translated chapter's existing text — it
  # never re-translates, so there's nothing to run it against until the
  # chapter has a translated_output to read.
  def chapter_qa_single_chapter_translated
    if chapter_start != chapter_end
      errors.add(:chapter_end, "must equal chapter_start — chapter_qa reviews one chapter at a time")
    end

    unless novel.chapters.where(status: %w[translated reviewed]).exists?(number: chapter_start)
      errors.add(:chapter_start, "must be a translated chapter")
    end
  end

  def broadcast_status_change
    if cancellable?
      broadcast_replace_later_to(
        "translation_jobs",
        target: "active-job-#{id}",
        partial: "novels/active_job_item",
        locals: { job: self, show_novel: true }
      )
    else
      broadcast_remove_to "translation_jobs", target: "active-job-#{id}"
      fresh_novel = Novel.includes(chapters: [], translation_jobs: [])
                         .with_attached_cover_art
                         .find(novel_id)
      broadcast_replace_later_to(
        "translation_jobs",
        target: "novel-card-#{novel_id}",
        partial: "novels/card",
        locals: { novel: fresh_novel }
      )
    end

    broadcast_preread_entries_status if preread?
  end

  # Pushes the Review tab's "Preread Bible Entries" card up to date on every
  # status change of a preread job — every tab panel loads eagerly and stays
  # in the DOM even while hidden (see tabs_controller.ts), so this reaches
  # the card whether or not the Review tab happens to be the visible one.
  # Subscribed to from novels/show.html.erb (the persistent page shell, not
  # the swappable tab-frame content, so the subscription survives tab
  # switches) via turbo_stream_from "novel_#{novel_id}_preread".
  def broadcast_preread_entries_status
    breakdown = novel.pending_preread_breakdown
    broadcast_replace_later_to(
      "novel_#{novel_id}_preread",
      target: "preread-entries-status",
      partial: "chapter_review/preread_entries_status",
      locals: { novel: novel, pending_count: breakdown[:total], pending_breakdown: breakdown[:by_category] }
    )
  end
end
