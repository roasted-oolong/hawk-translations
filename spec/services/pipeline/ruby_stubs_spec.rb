require "rails_helper"

RSpec.describe "Pipeline::Ruby stub implementations" do
  {
    "preread"                 => Pipeline::Ruby::Preread,
    "translate_batch"         => Pipeline::Ruby::TranslateBatch,
    "bible_build"             => Pipeline::Ruby::BibleBuild,
    "post_translation_review" => Pipeline::Ruby::PostTranslationReview,
    "voice_calibration"       => Pipeline::Ruby::VoiceCalibration
  }.each do |job_type, klass|
    it "#{klass} raises NotImplementedError for a #{job_type} job" do
      job = build_stubbed(:translation_job, job_type: job_type)

      expect { klass.call(job) }.to raise_error(NotImplementedError)
    end
  end
end
