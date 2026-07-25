require "rails_helper"

RSpec.describe "Pipeline::Ruby stub implementations" do
  # Preread and BibleBuild are built (R6) — see
  # spec/services/pipeline/ruby/preread_runner_spec.rb — and excluded here.
  {
    "translate_batch"         => Pipeline::Ruby::TranslateBatch,
    "post_translation_review" => Pipeline::Ruby::PostTranslationReview,
    "voice_calibration"       => Pipeline::Ruby::VoiceCalibration
  }.each do |job_type, klass|
    it "#{klass} raises NotImplementedError for a #{job_type} job" do
      job = build_stubbed(:translation_job, job_type: job_type)

      expect { klass.call(job) }.to raise_error(NotImplementedError)
    end
  end
end
