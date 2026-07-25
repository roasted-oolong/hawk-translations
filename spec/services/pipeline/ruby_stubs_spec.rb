require "rails_helper"

RSpec.describe "Pipeline::Ruby stub implementations" do
  # Preread and BibleBuild are built (R6) — see
  # spec/services/pipeline/ruby/preread_runner_spec.rb. PostTranslationReview
  # and VoiceCalibration are built (R5) — see
  # spec/services/pipeline/ruby/post_translation_review_spec.rb and
  # spec/services/pipeline/ruby/voice_calibration_spec.rb. All three are
  # excluded here; only TranslateBatch (R4) remains an actual stub.
  {
    "translate_batch" => Pipeline::Ruby::TranslateBatch
  }.each do |job_type, klass|
    it "#{klass} raises NotImplementedError for a #{job_type} job" do
      job = build_stubbed(:translation_job, job_type: job_type)

      expect { klass.call(job) }.to raise_error(NotImplementedError)
    end
  end
end
