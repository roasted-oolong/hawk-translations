module Pipeline
  module Ruby
    # Stub — PIPELINE_IMPL_TRANSLATE_BATCH defaults to "python", so this is
    # unreachable until a later milestone ports translate_batch.py to Ruby.
    class TranslateBatch
      def self.call(_job)
        raise NotImplementedError, "Pipeline::Ruby::TranslateBatch has no implementation yet"
      end
    end
  end
end
