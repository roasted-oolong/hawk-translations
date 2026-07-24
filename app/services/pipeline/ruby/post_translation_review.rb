module Pipeline
  module Ruby
    # Stub — PIPELINE_IMPL_POST_TRANSLATION_REVIEW defaults to "python", so
    # this is unreachable until a later milestone ports run_review.py to Ruby.
    class PostTranslationReview
      def self.call(_job)
        raise NotImplementedError, "Pipeline::Ruby::PostTranslationReview has no implementation yet"
      end
    end
  end
end
