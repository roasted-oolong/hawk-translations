# ---------------------------------------------------------------------------
# Pipeline::Ruby::Preread
#
# Public entry point PipelineDispatcher#dispatch_ruby calls for "preread"
# jobs. Thin: supplies PrereadRunner its own chapter-discovery predicate
# (Korean source present, no translated .txt yet) and batch size — matches
# PipelineDispatcher#run_preread's hardcoded "--batch-size 2" (preserved,
# not unified with bible_build's default of 5 — see
# docs/RAILS_REFACTOR_PLAN.md's R6 section).
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class Preread
      BATCH_SIZE = 2

      def self.call(job)
        PrereadRunner.call(
          job,
          discovery:  ->(chapters_dir) { PrereadRunner::ChapterDiscovery.find_untranslated_chapters(chapters_dir) },
          batch_size: BATCH_SIZE
        )
      end
    end
  end
end
