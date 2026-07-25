require "rails_helper"

RSpec.describe Pipeline::Ruby::Preread do
  it "calls PrereadRunner with the untranslated-chapters discovery predicate and batch size 2" do
    job = build_stubbed(:translation_job, job_type: "preread")
    captured = nil

    allow(Pipeline::Ruby::PrereadRunner).to receive(:call) do |received_job, discovery:, batch_size:|
      captured = { job: received_job, discovery: discovery, batch_size: batch_size }
      [ "ok", "", true ]
    end

    result = described_class.call(job)

    expect(result).to eq([ "ok", "", true ])
    expect(captured[:job]).to eq(job)
    expect(captured[:batch_size]).to eq(2)

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ch1_korean"), "x")
      File.write(File.join(dir, "ch2_korean"), "x")
      File.write(File.join(dir, "Chapter 2.txt"), "translated")

      expect(captured[:discovery].call(dir)).to eq([ 1 ])
    end
  end
end
