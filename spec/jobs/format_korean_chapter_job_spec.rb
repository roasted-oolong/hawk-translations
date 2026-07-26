require "rails_helper"

RSpec.describe FormatKoreanChapterJob, type: :job do
  let(:novel_dir) { Dir.mktmpdir("format_korean_job_spec") }
  let(:novel)     { create(:novel, directory_name: File.basename(novel_dir)) }
  let(:chapter)   { create(:chapter, novel: novel, number: 3, status: "untranslated") }

  let(:original_text) { "안녕\n하세요" }
  let(:cleaned_text)  { "안녕하세요" }

  # HAWK_PROJECT_ROOT is scoped to a throwaway tmpdir (not Rails.root) since
  # the job now also writes a "Chapter <N> (Korean).txt" disk copy via
  # KoreanSourceDiskWriter — pointing it at Rails.root would litter the repo
  # with a real "novel-N/chapters/" directory on every test run.
  around do |example|
    orig = ENV["HAWK_PROJECT_ROOT"]
    ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)
    example.run
  ensure
    ENV["HAWK_PROJECT_ROOT"] = orig
    FileUtils.rm_rf(novel_dir)
  end

  before do
    chapter.korean_source.attach(
      io:           StringIO.new(original_text),
      filename:     "ch03_korean.txt",
      content_type: "text/plain"
    )
  end

  def stub_cleaner(output:, success: true)
    stdin_double  = instance_double(IO, binmode: nil, write: nil, close: nil)
    stdout_double = instance_double(IO, read: output)
    stderr_double = instance_double(IO, read: success ? "" : "something went wrong")
    status        = instance_double(Process::Status, success?: success)
    wait_thread   = instance_double(Thread, join: true, value: status)

    allow(Open3).to receive(:popen3).and_yield(stdin_double, stdout_double, stderr_double, wait_thread)
  end

  describe "#perform" do
    context "when the cleaner succeeds" do
      it "replaces the Korean source attachment with the cleaned content" do
        stub_cleaner(output: cleaned_text)

        described_class.perform_now(chapter.id)

        expect(chapter.reload.korean_source.download).to eq(cleaned_text)
      end

      it "preserves the original filename" do
        stub_cleaner(output: cleaned_text)

        described_class.perform_now(chapter.id)

        expect(chapter.reload.korean_source.filename.to_s).to eq("ch03_korean.txt")
      end
    end

    context "when the cleaner fails" do
      it "leaves the original attachment intact" do
        stub_cleaner(output: "", success: false)

        expect { described_class.perform_now(chapter.id) }
          .not_to change { chapter.korean_source.reload.checksum }
      end
    end

    context "when the chapter does not exist" do
      it "does nothing" do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end
    end

    context "when no Korean source is attached" do
      it "does not call the cleaner" do
        chapter.korean_source.detach
        expect(Open3).not_to receive(:popen3)
        described_class.perform_now(chapter.id)
      end
    end
  end

  describe "PIPELINE_IMPL_FORMATTER=ruby" do
    around do |example|
      orig = ENV["PIPELINE_IMPL_FORMATTER"]
      ENV["PIPELINE_IMPL_FORMATTER"] = "ruby"
      example.run
    ensure
      ENV["PIPELINE_IMPL_FORMATTER"] = orig
    end

    it "routes through Pipeline::Ruby::FormatKoreanChapter instead of Open3, on success" do
      result = Pipeline::Ruby::FormatKoreanChapter::Result.new(output: cleaned_text)
      expect(Pipeline::Ruby::FormatKoreanChapter).to receive(:call).with(original_text).and_return(result)
      expect(Open3).not_to receive(:popen3)

      described_class.perform_now(chapter.id)

      expect(chapter.reload.korean_source.download).to eq(cleaned_text)
    end

    it "leaves the original attachment intact and logs when the Ruby orchestrator fails" do
      result = Pipeline::Ruby::FormatKoreanChapter::Result.new(error_message: "boom")
      allow(Pipeline::Ruby::FormatKoreanChapter).to receive(:call).and_return(result)
      expect(Rails.logger).to receive(:error).with(/boom/)

      expect { described_class.perform_now(chapter.id) }
        .not_to change { chapter.korean_source.reload.checksum }
    end
  end
end
