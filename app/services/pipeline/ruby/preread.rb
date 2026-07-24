module Pipeline
  module Ruby
    # Stub — PIPELINE_IMPL_PREREAD defaults to "python", so this is
    # unreachable until a later milestone ports run_preread.py to Ruby.
    class Preread
      def self.call(_job)
        raise NotImplementedError, "Pipeline::Ruby::Preread has no implementation yet"
      end
    end
  end
end
