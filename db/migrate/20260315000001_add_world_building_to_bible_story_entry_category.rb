class AddWorldBuildingToBibleStoryEntryCategory < ActiveRecord::Migration[8.1]
  # The category column is string-backed with no DB-level check constraint —
  # validation lives entirely in the model enum. No column change required;
  # this migration exists as a documented record of the schema intent change.
  def change
    # No-op at the database level. The world_building value is added to the
    # BibleStoryEntry enum in the model. Recorded here so the migration
    # history reflects when the category set was extended.
  end
end
