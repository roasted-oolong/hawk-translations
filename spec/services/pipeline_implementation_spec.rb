require "rails_helper"

RSpec.describe PipelineImplementation do
  ENV_VAR_BY_JOB_TYPE = {
    "preread"                 => "PIPELINE_IMPL_PREREAD",
    "translate_batch"         => "PIPELINE_IMPL_TRANSLATE_BATCH",
    "bible_build"             => "PIPELINE_IMPL_BIBLE_BUILD",
    "post_translation_review" => "PIPELINE_IMPL_POST_TRANSLATION_REVIEW",
    "voice_calibration"       => "PIPELINE_IMPL_VOICE_CALIBRATION"
  }.freeze

  around do |example|
    originals = ENV_VAR_BY_JOB_TYPE.values.index_with { |var| ENV[var] }
    example.run
    originals.each { |var, value| ENV[var] = value }
  end

  ENV_VAR_BY_JOB_TYPE.each do |job_type, env_var|
    describe "#for(#{job_type.inspect})" do
      it "defaults to :python when #{env_var} is unset" do
        ENV.delete(env_var)
        expect(described_class.for(job_type)).to eq(:python)
      end

      it "returns :ruby when #{env_var}=ruby" do
        ENV[env_var] = "ruby"
        expect(described_class.for(job_type)).to eq(:ruby)
      end

      it "raises a clear error for an unrecognized #{env_var} value" do
        ENV[env_var] = "rby"
        expect { described_class.for(job_type) }.to raise_error(/#{env_var}/)
      end
    end
  end

  it "only affects the one job type's env var, not the others" do
    ENV["PIPELINE_IMPL_TRANSLATE_BATCH"] = "ruby"
    ENV.delete("PIPELINE_IMPL_PREREAD")

    expect(described_class.for("translate_batch")).to eq(:ruby)
    expect(described_class.for("preread")).to eq(:python)
  end

  it "raises for a job_type with no mapped env var" do
    expect { described_class.for("not_a_real_job_type") }.to raise_error(ArgumentError)
  end
end
