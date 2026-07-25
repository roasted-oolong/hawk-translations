# ---------------------------------------------------------------------------
# Pipeline::Ruby::BibleBuild
#
# Public entry point PipelineDispatcher#dispatch_ruby calls for
# "bible_build" jobs. Thin: supplies PrereadRunner its own chapter-discovery
# predicate (any chapter with a Korean source file, translated or not) and
# batch size — matches run_bible_build.py's argparse default of 5
# (PipelineDispatcher#run_bible_build passes no --batch-size flag today).
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class BibleBuild
      BATCH_SIZE = 5

      def self.call(job)
        PrereadRunner.call(
          job,
          discovery:  ->(chapters_dir) { PrereadRunner::ChapterDiscovery.find_all_korean_chapters(chapters_dir) },
          batch_size: BATCH_SIZE
        )
      end
    end
  end
end
