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
    post_translation_review:  "post_translation_review"
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

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  scope :recent,     -> { order(created_at: :desc) }
  scope :for_novel,  ->(novel) { where(novel: novel) }
  scope :cancellable, -> { where(status: %w[queued running]) }

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

  def cancel!
    transaction do
      update!(status: :cancelled)
      if preread?
        novel.chapters
          .where(number: chapter_start..chapter_end, status: "prereading")
          .update_all(status: "preread_failed")
      end
    end
  end

  private

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
end
