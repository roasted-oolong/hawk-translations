# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# Embeddable concern spec
#
# Tests the contract the concern establishes:
# - Including classes must implement #embeddable_text
# - #embeddable_text raises NotImplementedError if not overridden
# - The after_save hook enqueues GenerateEmbeddingJob
#
# Each concrete model's spec tests that its own #embeddable_text includes
# the right fields. This spec tests only the shared contract.
# =============================================================================
RSpec.describe Embeddable, type: :model do
  # Build an anonymous ActiveRecord-like class that includes the concern
  # but does NOT implement embeddable_text — lets us test the guard.
  let(:bare_class) do
    Class.new do
      # Stub must be defined BEFORE include so it exists when the included
      # block calls after_save :enqueue_embedding_job.
      def self.after_save(*); end

      include Embeddable
    end
  end

  describe "#embeddable_text" do
    it "raises NotImplementedError on a class that does not implement it" do
      instance = bare_class.new
      expect { instance.embeddable_text }.to raise_error(NotImplementedError, /embeddable_text/)
    end
  end

  describe "after_save hook via a real model" do
    it "enqueues GenerateEmbeddingJob when a bible_character is saved" do
      novel = create(:novel)
      expect {
        create(:bible_character, novel: novel)
      }.to have_enqueued_job(GenerateEmbeddingJob)
    end

    it "enqueues GenerateEmbeddingJob when a bible_location is saved" do
      novel = create(:novel)
      expect {
        create(:bible_location, novel: novel)
      }.to have_enqueued_job(GenerateEmbeddingJob)
    end

    it "enqueues GenerateEmbeddingJob when a bible_terminology is saved" do
      novel = create(:novel)
      expect {
        create(:bible_terminology, novel: novel)
      }.to have_enqueued_job(GenerateEmbeddingJob)
    end

    it "enqueues GenerateEmbeddingJob when a bible_cultural_phrase is saved" do
      novel = create(:novel)
      expect {
        create(:bible_cultural_phrase, novel: novel)
      }.to have_enqueued_job(GenerateEmbeddingJob)
    end

    it "enqueues GenerateEmbeddingJob when a bible_story_entry is saved" do
      novel = create(:novel)
      expect {
        create(:bible_story_entry, novel: novel)
      }.to have_enqueued_job(GenerateEmbeddingJob)
    end
  end
end
