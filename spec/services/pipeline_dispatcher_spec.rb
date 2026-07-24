require "rails_helper"

RSpec.describe PipelineDispatcher do
  let(:novel) { create(:novel, directory_name: "idols-rewind") }
  let(:user)  { create(:user) }
  let(:job)   { create(:translation_job, novel: novel, user: user, chapter_start: 3, chapter_end: 5) }

  before do
    @orig_root = ENV["HAWK_PROJECT_ROOT"]
    ENV["HAWK_PROJECT_ROOT"] = "/tmp/hawk_project_root"
  end

  after do
    ENV["HAWK_PROJECT_ROOT"] = @orig_root
  end

  def stub_subprocess(status:, exit_code:, stdout: "", stderr: "")
    result = Pipeline::Subprocess::Result.new(
      status:       status,
      exit_code:    exit_code,
      started_at:   Time.now,
      finished_at:  Time.now,
      command_name: job.job_type,
      stdout:       stdout,
      stderr:       stderr,
      bytes_stdout: stdout.bytesize,
      bytes_stderr: stderr.bytesize
    )
    allow(Pipeline::Subprocess).to receive(:run).and_return(result)
    result
  end

  describe "#call" do
    it "delegates to Pipeline::Subprocess.run with the job type as name and HAWK_JOB_ID in env" do
      stub_subprocess(status: :completed, exit_code: 0, stdout: "done")

      described_class.call(job)

      expect(Pipeline::Subprocess).to have_received(:run).with(
        array_including("python3", include("run_preread.py")),
        env: hash_including("HAWK_JOB_ID" => job.id.to_s),
        timeout: PipelineDispatcher::EXECUTE_TIMEOUT,
        name: "preread"
      )
    end

    it "adapts a successful Result into [stdout, stderr, true]" do
      stub_subprocess(status: :completed, exit_code: 0, stdout: "translated text", stderr: "")

      expect(described_class.call(job)).to eq([ "translated text", "", true ])
    end

    it "adapts a nonzero-exit Result into [stdout, stderr, false]" do
      stub_subprocess(status: :completed, exit_code: 1, stdout: "", stderr: "boom")

      expect(described_class.call(job)).to eq([ "", "boom", false ])
    end

    it "adapts a timed-out Result into success? false, without raising" do
      stub_subprocess(status: :timed_out, exit_code: nil, stdout: "partial", stderr: "")

      expect(described_class.call(job)).to eq([ "partial", "", false ])
    end

    it "rescues a raised error from Subprocess.run into a Dispatch error triple" do
      allow(Pipeline::Subprocess).to receive(:run).and_raise(Errno::ENOENT, "no such file")

      stdout, stderr, success = described_class.call(job)

      expect(success).to eq(false)
      expect(stdout).to eq("")
      expect(stderr).to include("Dispatch error")
    end

    it "returns a failure triple for an unknown job_type without touching Subprocess" do
      job.update_column(:job_type, "not_a_real_type")

      expect(Pipeline::Subprocess).not_to receive(:run)
      stdout, stderr, success = described_class.call(job)

      expect(success).to eq(false)
      expect(stderr).to include("Unknown job_type")
    end
  end
end
