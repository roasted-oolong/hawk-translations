module Pipeline
  module Ruby
    # Stub — PIPELINE_IMPL_VOICE_CALIBRATION defaults to "python", so this is
    # unreachable until a later milestone ports calibrate-voice.py to Ruby.
    class VoiceCalibration
      def self.call(_job)
        raise NotImplementedError, "Pipeline::Ruby::VoiceCalibration has no implementation yet"
      end
    end
  end
end
