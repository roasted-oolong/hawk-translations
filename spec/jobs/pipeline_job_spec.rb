require "rails_helper"

RSpec.describe PipelineJob, type: :job do
  describe "#perform — voice calibration" do
    let(:novel)   { create(:novel) }
    let(:user)    { create(:user) }
    let!(:chapter) { create(:chapter, novel: novel, number: 5, status: "reviewed") }
    let(:job)     { create(:translation_job, :voice_calibration, novel: novel, user: user,
                           chapter_start: 5, chapter_end: 5) }

    def dispatch_with(stdout:, success: true)
      allow(PipelineDispatcher).to receive(:call).and_return([stdout, "", success])
      described_class.new.perform(job.id)
      job.reload
    end

    context "when the script outputs valid JSON with a new_pattern card" do
      let(:payload) do
        {
          "cards" => [
            {
              "id"                   => "new_pattern_0",
              "card_type"            => "new_pattern",
              "heading"              => "Passage 1 — Dry narrator",
              "chapter_ref"          => "Chapter 5",
              "quote"                => "He said nothing.",
              "what_it_demonstrates" => "Restraint.",
              "wrong_version"        => "He stayed silent, unable to speak.",
              "rule"                 => "The narrator does not explain what silence means."
            }
          ]
        }
      end

      it "marks the job completed and stores the JSON payload" do
        dispatch_with(stdout: payload.to_json)

        expect(job.status).to eq("completed")
        stored = JSON.parse(job.result_payload)
        expect(stored["cards"].first["card_type"]).to eq("new_pattern")
        expect(stored["cards"].first["heading"]).to eq("Passage 1 — Dry narrator")
      end
    end

    context "when the script outputs a retirement card whose heading matches a passage" do
      let!(:passage) do
        novel.voice_calibration_passages.create!(
          heading:  "Passage 3 — Old pattern",
          quote:    "Some quote",
          rule:     "Some rule",
          position: 0
        )
      end

      let(:payload) do
        {
          "cards" => [
            {
              "id"        => "retirement_0",
              "card_type" => "retirement",
              "heading"   => "Passage 3 — Old pattern",
              "reason"    => "Superseded by new pattern above."
            }
          ]
        }
      end

      it "resolves passage_id and quote on the retirement card" do
        dispatch_with(stdout: payload.to_json)

        stored = JSON.parse(job.result_payload)
        card   = stored["cards"].first
        expect(card["passage_id"]).to eq(passage.id)
        expect(card["quote"]).to eq("Some quote")
      end
    end

    context "when the retirement card heading has no matching passage" do
      let(:payload) do
        {
          "cards" => [
            {
              "id"        => "retirement_0",
              "card_type" => "retirement",
              "heading"   => "Passage 99 — Does not exist",
              "reason"    => "Redundant."
            }
          ]
        }
      end

      it "stores nil for passage_id and quote rather than raising" do
        dispatch_with(stdout: payload.to_json)

        stored = JSON.parse(job.result_payload)
        expect(stored["cards"].first["passage_id"]).to be_nil
        expect(stored["cards"].first["quote"]).to be_nil
      end
    end

    context "when the DB passage heading lacks the 'Passage N — ' prefix the model cites" do
      # Passages seeded before the review flow existed were backfilled with just the
      # descriptive title (no "Passage N — " prefix), but the model always cites the
      # heading as it appears in voice_calibration.md, which does include the prefix.
      let!(:passage) do
        novel.voice_calibration_passages.create!(
          heading:  "Old pattern without a prefix",
          quote:    "Some quote",
          rule:     "Some rule",
          position: 0
        )
      end

      let(:payload) do
        {
          "cards" => [
            {
              "id"        => "retirement_0",
              "card_type" => "retirement",
              "heading"   => "Passage 3 — Old pattern without a prefix",
              "reason"    => "Superseded by new pattern above."
            }
          ]
        }
      end

      it "still resolves passage_id by matching on the description, ignoring the prefix" do
        dispatch_with(stdout: payload.to_json)

        stored = JSON.parse(job.result_payload)
        expect(stored["cards"].first["passage_id"]).to eq(passage.id)
      end
    end

    context "when the script outputs non-JSON (e.g. a crash traceback)" do
      it "falls back to storing stdout as-is and still marks the job failed" do
        dispatch_with(stdout: "Traceback (most recent call last):\n  ...", success: false)

        expect(job.status).to eq("failed")
        expect(job.result_payload).to include("Traceback")
      end
    end

    context "when the script succeeds but stdout is not JSON" do
      it "stores stdout as-is rather than crashing" do
        dispatch_with(stdout: "unexpected plain text output")

        expect(job.status).to eq("completed")
        expect(job.result_payload).to eq("unexpected plain text output")
      end
    end

    context "when the job is cancelled while the script is running" do
      it "leaves the status as cancelled and does not overwrite it" do
        allow(PipelineDispatcher).to receive(:call) do
          job.cancel!
          ["{\"cards\":[]}", "", true]
        end

        described_class.new.perform(job.id)
        job.reload

        expect(job.status).to eq("cancelled")
      end
    end
  end

  describe "#perform — translate_batch" do
    let(:novel)     { create(:novel) }
    let(:user)      { create(:user) }
    let!(:chapter1) { create(:chapter, novel: novel, number: 1, status: "preread") }
    let!(:chapter2) { create(:chapter, novel: novel, number: 2, status: "preread") }
    let(:job)       { create(:translation_job, :translate_batch, novel: novel, user: user,
                             chapter_start: 1, chapter_end: 2) }

    def with_project_root(root)
      original = ENV["HAWK_PROJECT_ROOT"]
      ENV["HAWK_PROJECT_ROOT"] = root
      yield
    ensure
      ENV["HAWK_PROJECT_ROOT"] = original
    end

    def write_output(root, chapter_num, text)
      dir = File.join(root, novel.directory_name, "chapters")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "Chapter #{chapter_num}.txt"), text)
    end

    context "when the batch fails partway through (one chapter written, one not)" do
      it "attaches and marks translated only the chapter whose output file exists, per-chapter rather than all-or-nothing" do
        Dir.mktmpdir do |root|
          with_project_root(root) do
            write_output(root, 1, "Chapter one translated.")
            # No output file written for chapter 2 — it failed.

            allow(PipelineDispatcher).to receive(:call)
              .and_return([ "1 chapter(s) translated.", "Chapter 2: cli_failure — boom", false ])

            described_class.new.perform(job.id)
            job.reload
            chapter1.reload
            chapter2.reload

            expect(job.status).to eq("failed")
            expect(chapter1.status).to eq("translated")
            expect(chapter1.translated_output).to be_attached
            expect(chapter2.status).to eq("preread")
            expect(chapter2.translated_output).not_to be_attached
          end
        end
      end
    end

    context "when the whole batch succeeds" do
      it "attaches and marks every chapter translated" do
        Dir.mktmpdir do |root|
          with_project_root(root) do
            write_output(root, 1, "Chapter one translated.")
            write_output(root, 2, "Chapter two translated.")

            allow(PipelineDispatcher).to receive(:call)
              .and_return([ "2 chapter(s) translated.", "", true ])

            described_class.new.perform(job.id)
            job.reload
            chapter1.reload
            chapter2.reload

            expect(job.status).to eq("completed")
            expect(chapter1.status).to eq("translated")
            expect(chapter2.status).to eq("translated")
          end
        end
      end
    end
  end
end
