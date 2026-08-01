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

    it "raises for a job_type PipelineImplementation doesn't recognize, without touching Subprocess" do
      job.update_column(:job_type, "not_a_real_type")

      expect(Pipeline::Subprocess).not_to receive(:run)
      expect { described_class.call(job) }.to raise_error(ArgumentError)
    end
  end

  describe "#call with PIPELINE_IMPL_PREREAD=ruby" do
    around do |example|
      original = ENV["PIPELINE_IMPL_PREREAD"]
      ENV["PIPELINE_IMPL_PREREAD"] = "ruby"
      example.run
      ENV["PIPELINE_IMPL_PREREAD"] = original
    end

    it "routes to Pipeline::Ruby::Preread instead of Pipeline::Subprocess" do
      expect(Pipeline::Subprocess).not_to receive(:run)
      expect(Pipeline::Ruby::Preread).to receive(:call).with(job).and_return([ "ok", "", true ])

      expect(described_class.call(job)).to eq([ "ok", "", true ])
    end
  end

  describe "#call for a chapter_qa job" do
    let(:chapter) { create(:chapter, novel: novel, number: 7, status: "translated") }
    let(:qa_job) do
      create(:translation_job, novel: novel, user: user, job_type: "chapter_qa",
             chapter_start: chapter.number, chapter_end: chapter.number)
    end

    it "routes straight to Pipeline::Ruby::ChapterQa without consulting PipelineImplementation or Subprocess" do
      expect(PipelineImplementation).not_to receive(:for)
      expect(Pipeline::Subprocess).not_to receive(:run)
      expect(Pipeline::Ruby::ChapterQa).to receive(:call).with(qa_job).and_return([ "ok", "", true ])

      expect(described_class.call(qa_job)).to eq([ "ok", "", true ])
    end

    it "ignores PIPELINE_IMPL_CHAPTER_QA even if someone sets it, since chapter_qa always bypasses that lookup" do
      original = ENV["PIPELINE_IMPL_CHAPTER_QA"]
      ENV["PIPELINE_IMPL_CHAPTER_QA"] = "python"
      begin
        expect(Pipeline::Ruby::ChapterQa).to receive(:call).with(qa_job).and_return([ "ok", "", true ])
        expect(described_class.call(qa_job)).to eq([ "ok", "", true ])
      ensure
        ENV["PIPELINE_IMPL_CHAPTER_QA"] = original
      end
    end
  end
end
