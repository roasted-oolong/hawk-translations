# frozen_string_literal: true

# A rendering convention (how dialogue, thoughts, titles, onomatopoeia, etc.
# are typographically rendered in English) — either a global default
# (novel_id: nil) or one novel's override/addition, keyed by rule_key.
#
# Defaults are American-literary-convention starting points, not mandates.
# A novel that wants a different convention for a given rule_key overrides
# it with its own row; see .effective_for for how the two are resolved.
class RenderingRule < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :novel, optional: true

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :rule_key, presence: true, uniqueness: { scope: :novel_id }
  validates :name,     presence: true
  validates :guidance, presence: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  scope :defaults,   -> { where(novel_id: nil) }
  scope :for_novel,  ->(novel) { where(novel: novel) }
  scope :ordered,    -> { order(:position, :id) }

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # The rule set a novel actually translates under: each default rule_key is
  # replaced by that novel's own row when one exists, in the defaults' own
  # order; novel-specific rule_keys with no matching default (pure additions)
  # are appended afterward, ordered among themselves.
  def self.effective_for(novel)
    defaults_by_key = defaults.ordered.index_by(&:rule_key)
    overrides_by_key = for_novel(novel).ordered.index_by(&:rule_key)

    resolved = defaults_by_key.map { |key, default_rule| overrides_by_key[key] || default_rule }
    additions = overrides_by_key.values_at(*(overrides_by_key.keys - defaults_by_key.keys))

    resolved + additions
  end
end
