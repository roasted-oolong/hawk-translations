# frozen_string_literal: true

# =============================================================================
# BibleDocSynced
#
# Concern included by all five bible entry models. Keeps that novel's
# bible/*.md file for this model's category in sync with the DB on every
# write, closing the drift docs/PREREAD_STAGING_DESIGN.md's Part 3 exists to
# fix: editing an entry through its own edit page used to update the DB but
# never touch the file, so the two silently drifted apart. After every
# create/update/destroy, the corresponding file is fully regenerated from
# all of that novel's current rows for this category — mirrors
# RenderingRulesController's "always fully rewrite, never patch in place"
# handling of rendering_guide.md, just triggered from the model instead of
# a controller (these five models have no other write path to hook).
#
# after_commit, not after_save, so a destroy clears the entry from the file
# exactly as reliably as a create/update writes it. Runs after the DB
# transaction commits, so a slow or failing file write can never roll back
# or block the real (DB) save — this is best-effort mirroring, not the
# source of truth itself; failures are logged and swallowed rather than
# raised, matching RenderingRulesController#regenerate_guide!'s
# raise_on_error: false precedent for exactly this kind of non-critical
# sync.
#
# 1. Each including class MUST implement #bible_doc_category — a symbol
#    key into Pipeline::BibleEntryDocWriter::HEADER_TITLE/FILE_MAP,
#    identifying which bible/*.md file and field layout this model writes
#    to. Raises NotImplementedError at call time if not overridden.
#
# Usage:
#   class BibleCharacter < ApplicationRecord
#     include BibleDocSynced
#
#     def bible_doc_category
#       :characters
#     end
#   end
# =============================================================================
module BibleDocSynced
  extend ActiveSupport::Concern

  included do
    after_commit :sync_bible_doc
  end

  # ---------------------------------------------------------------------------
  # Contract — must be implemented by the including class.
  # ---------------------------------------------------------------------------
  def bible_doc_category
    raise NotImplementedError,
          "#{self.class.name} must implement #bible_doc_category to use the BibleDocSynced concern."
  end

  private

  def sync_bible_doc
    Pipeline::BibleEntryDocWriter.new(novel_dir_for_doc_sync, bible_doc_category).write(sibling_records_for_doc_sync)
  rescue StandardError => e
    Rails.logger.error(
      "[BibleDocSynced] failed to sync #{bible_doc_category} doc for novel=#{novel_id}: #{e.class}: #{e.message}"
    )
  end

  def novel_dir_for_doc_sync
    root = ENV.fetch("HAWK_PROJECT_ROOT", "")
    return nil if root.blank? || novel.directory_name.blank?
    File.join(root, novel.directory_name)
  end

  # All of this novel's current rows for this model's category, oldest
  # first — stable ordering across regenerations regardless of which
  # record's save triggered this run.
  def sibling_records_for_doc_sync
    self.class.where(novel_id: novel_id).order(:id)
  end
end
