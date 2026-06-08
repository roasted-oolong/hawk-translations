class VoiceCalibrationPassage < ApplicationRecord
  belongs_to :novel

  validates :heading, :quote, :rule, presence: true

  scope :ordered, -> { order(:position, :id) }
end
