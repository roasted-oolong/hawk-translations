module Pipeline
  module Ruby
    # Stub — PIPELINE_IMPL_BIBLE_BUILD defaults to "python", so this is
    # unreachable until a later milestone ports run_bible_build.py to Ruby.
    class BibleBuild
      def self.call(_job)
        raise NotImplementedError, "Pipeline::Ruby::BibleBuild has no implementation yet"
      end
    end
  end
end
