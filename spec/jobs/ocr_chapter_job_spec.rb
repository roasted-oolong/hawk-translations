require "rails_helper"

RSpec.describe OcrChapterJob, type: :job do
  let(:novel)   { create(:novel) }
  let(:chapter) { create(:chapter, novel: novel, number: 3, status: "untranslated") }

  let(:scratch_dir) { Dir.mktmpdir("chapter_photos_spec") }
  let(:image_paths) do
    [ "001.jpg", "002.jpg" ].map do |name|
      path = File.join(scratch_dir, name)
      File.write(path, "fake image bytes")
      path
    end
  end

  let(:transcribed_text) { "안녕하세요\n\n반갑습니다" }

  around do |example|
    orig = ENV["HAWK_PROJECT_ROOT"]
    ENV["HAWK_PROJECT_ROOT"] = Rails.root.to_s
    example.run
  ensure
    ENV["HAWK_PROJECT_ROOT"] = orig
  end

  def stub_ocr(output:, success: true, signaled: false, termsig: nil)
    stdin_double  = instance_double(IO, binmode: nil, write: nil, close: nil)
    stdout_double = instance_double(IO, read: output)
    stderr_double = instance_double(IO, read: success ? "" : "something went wrong")
    status        = instance_double(Process::Status, success?: success, signaled?: signaled, termsig: termsig)
    wait_thread   = instance_double(Thread, join: true, value: status)

    allow(Open3).to receive(:popen3).and_yield(stdin_double, stdout_double, stderr_double, wait_thread)
  end

  describe "#perform" do
    context "when OCR succeeds" do
      before { stub_ocr(output: transcribed_text) }

      it "attaches the transcribed text as the Korean source" do
        described_class.perform_now(chapter.id, image_paths)

        expect(chapter.reload.korean_source).to be_attached
        expect(chapter.korean_source.download).to eq(transcribed_text)
        expect(chapter.korean_source.content_type).to eq("text/plain")
      end

      it "enqueues FormatKoreanChapterJob to clean up the OCR output" do
        expect {
          described_class.perform_now(chapter.id, image_paths)
        }.to have_enqueued_job(FormatKoreanChapterJob).with(chapter.id)
      end

      it "invokes the OCR script with the image paths in order" do
        described_class.perform_now(chapter.id, image_paths)

        expect(Open3).to have_received(:popen3) do |*args|
          expect(args.last(image_paths.size)).to eq(image_paths)
        end
      end

      it "deletes the scratch directory afterwards" do
        described_class.perform_now(chapter.id, image_paths)

        expect(Dir.exist?(scratch_dir)).to be false
      end
    end

    context "when the OCR script fails" do
      before { stub_ocr(output: "", success: false) }

      it "does not attach anything" do
        described_class.perform_now(chapter.id, image_paths)

        expect(chapter.reload.korean_source).not_to be_attached
      end

      it "does not enqueue the cleanup job" do
        expect {
          described_class.perform_now(chapter.id, image_paths)
        }.not_to have_enqueued_job(FormatKoreanChapterJob)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/OcrChapterJob/)
        described_class.perform_now(chapter.id, image_paths)
      end

      it "still deletes the scratch directory" do
        described_class.perform_now(chapter.id, image_paths)

        expect(Dir.exist?(scratch_dir)).to be false
      end

      it "marks the chapter as ocr_failed so the failure is visible in the UI" do
        described_class.perform_now(chapter.id, image_paths)

        expect(chapter.reload.status).to eq("ocr_failed")
      end
    end

    context "when the OCR script is killed by a signal (e.g. out of memory)" do
      before { stub_ocr(output: "", success: false, signaled: true, termsig: 9) }

      it "logs a signal-specific error naming the signal, distinct from a normal script failure" do
        expect(Rails.logger).to receive(:error).with(/killed by signal 9/)
        described_class.perform_now(chapter.id, image_paths)
      end

      it "marks the chapter as ocr_failed" do
        described_class.perform_now(chapter.id, image_paths)

        expect(chapter.reload.status).to eq("ocr_failed")
      end
    end

    context "when the chapter does not exist" do
      it "does nothing and does not call the OCR script" do
        expect(Open3).not_to receive(:popen3)
        expect { described_class.perform_now(-1, image_paths) }.not_to raise_error
      end

      it "still deletes the scratch directory" do
        described_class.perform_now(-1, image_paths)

        expect(Dir.exist?(scratch_dir)).to be false
      end
    end
  end
end
