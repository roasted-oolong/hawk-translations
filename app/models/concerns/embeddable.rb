# frozen_string_literal: true

# =============================================================================
# Embeddable
#
# Concern included by all five bible entry models. Establishes two contracts:
#
# 1. Each including class MUST implement #embeddable_text — a method that
#    returns a single concatenated string of all fields meaningful for
#    semantic search. Raises NotImplementedError at call time if not overridden.
#
# 2. Enqueues GenerateEmbeddingJob after every save so embeddings stay in
#    sync with record content. The job itself guards against unnecessary
#    Voyage AI API calls via content_hash comparison.
#
# Usage:
#   class BibleCharacter < ApplicationRecord
#     include Embeddable
#
#     def embeddable_text
#       [ name, korean_name, role, ... ].compact.join(" ")
#     end
#   end
# =============================================================================
module Embeddable
  extend ActiveSupport::Concern

  included do
    after_save :enqueue_embedding_job
  end

  # ---------------------------------------------------------------------------
  # Contract — must be implemented by the including class.
  # Raises immediately with a clear message rather than silently returning nil.
  # ---------------------------------------------------------------------------
  def embeddable_text
    raise NotImplementedError,
          "#{self.class.name} must implement #embeddable_text to use the Embeddable concern."
  end

  private

  def enqueue_embedding_job
    GenerateEmbeddingJob.perform_later(self.class.name, id)
  end
end
