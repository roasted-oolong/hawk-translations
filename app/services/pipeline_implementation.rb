# ---------------------------------------------------------------------------
# PipelineImplementation
#
# Resolves, for a given job_type, whether PipelineDispatcher should run the
# legacy Python script or the in-process Ruby port. One env var per job
# type — not one parameterized var — because each job type migrates on its
# own release cadence (R1-R6 land one job type's Ruby port at a time), so
# flipping one shouldn't require touching the others. Mirrors config.py's
# existing TRANSLATION_BACKEND/CALIBRATION_BACKEND idiom of independent env
# vars per axis rather than a parsed mapping.
#
# These are migration flags, not permanent configuration — expected to be
# retired once every job type has a stable Ruby implementation.
#
# This is the only place a PIPELINE_IMPL_<TYPE> string literal is read and
# validated; nothing downstream re-parses or re-checks it.
# ---------------------------------------------------------------------------
class PipelineImplementation
  ENV_VAR_BY_JOB_TYPE = {
    "preread"                 => "PIPELINE_IMPL_PREREAD",
    "translate_batch"         => "PIPELINE_IMPL_TRANSLATE_BATCH",
    "bible_build"             => "PIPELINE_IMPL_BIBLE_BUILD",
    "post_translation_review" => "PIPELINE_IMPL_POST_TRANSLATION_REVIEW",
    "voice_calibration"       => "PIPELINE_IMPL_VOICE_CALIBRATION"
  }.freeze

  VALID_VALUES = %w[python ruby].freeze

  def self.for(job_type)
    env_var = ENV_VAR_BY_JOB_TYPE.fetch(job_type) do
      raise ArgumentError, "No PIPELINE_IMPL env var mapped for job_type: #{job_type.inspect}"
    end

    value = ENV.fetch(env_var, "python")
    unless VALID_VALUES.include?(value)
      raise "#{env_var}=#{value.inspect} is not a recognized pipeline implementation " \
            "(expected #{VALID_VALUES.join(' or ')})"
    end

    value.to_sym
  end
end
