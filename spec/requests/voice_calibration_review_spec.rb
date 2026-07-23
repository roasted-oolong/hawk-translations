require "rails_helper"

RSpec.describe "VoiceCalibrationReview", type: :request do
  let(:user)      { create(:user) }
  let(:novel_dir) { Dir.mktmpdir }
  let(:novel)     { create(:novel, directory_name: File.basename(novel_dir)) }
  let(:doc_path)  { File.join(novel_dir, "bible", "voice_calibration.md") }

  before do
    sign_in(user)
    FileUtils.mkdir_p(File.join(novel_dir, "bible"))
    File.write(doc_path, <<~MD)
      ## Passage 1 — Existing pattern

      > An existing quote.

      **The rule it demonstrates:** An existing rule.
    MD

    @orig_root = ENV["HAWK_PROJECT_ROOT"]
    ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)
  end

  after do
    ENV["HAWK_PROJECT_ROOT"] = @orig_root
    FileUtils.rm_rf(novel_dir)
  end

  describe "POST /novels/:novel_id/voice_calibration/review/commit" do
    let(:new_pattern_card) do
      {
        "id"                   => "new_pattern_0",
        "card_type"            => "new_pattern",
        "heading"               => "Passage 2 — New pattern",
        "chapter_ref"           => "Chapter 5",
        "quote"                 => "A freshly proposed quote.",
        "what_it_demonstrates"  => "It demonstrates something.",
        "wrong_version"         => "The wrong version.",
        "rule"                  => "The new rule text.",
        "decision"              => "accepted"
      }
    end

    before do
      create(:chapter, novel: novel, number: 1, status: "reviewed")
      create(:translation_job, :voice_calibration, :completed, novel: novel, user: user,
             result_payload: { cards: [ new_pattern_card ] }.to_json)
    end

    it "creates a VoiceCalibrationPassage for the accepted card" do
      expect {
        post novel_voice_calibration_review_commit_path(novel)
      }.to change(novel.voice_calibration_passages, :count).by(1)
    end

    it "appends the accepted pattern to voice_calibration.md so future runs see it" do
      post novel_voice_calibration_review_commit_path(novel)

      doc = File.read(doc_path)
      expect(doc).to include("Passage 1 — Existing pattern") # original content preserved
      expect(doc).to include("Passage 2 — New pattern")
      expect(doc).to include("A freshly proposed quote.")
      expect(doc).to include("The new rule text.")
    end

    context "when the same heading is accepted a second time with a revised rule" do
      before { post novel_voice_calibration_review_commit_path(novel) }

      let(:revised_card) { new_pattern_card.merge("rule" => "A revised rule.", "decision" => "accepted_revised") }

      before do
        create(:translation_job, :voice_calibration, :completed, novel: novel, user: user,
               result_payload: { cards: [ revised_card ] }.to_json)
      end

      it "does not duplicate the passage in the DB" do
        expect {
          post novel_voice_calibration_review_commit_path(novel)
        }.not_to change(novel.voice_calibration_passages, :count)
      end

      it "replaces the old block in voice_calibration.md rather than duplicating it" do
        post novel_voice_calibration_review_commit_path(novel)

        doc = File.read(doc_path)
        expect(doc.scan("Passage 2 — New pattern").size).to eq(1)
        expect(doc).to include("A revised rule.")
        expect(doc).not_to include("The new rule text.")
      end
    end

    context "with an accepted retirement card" do
      let!(:passage) do
        novel.voice_calibration_passages.create!(
          heading:  "Passage 1 — Existing pattern",
          quote:    "An existing quote.",
          rule:     "An existing rule.",
          position: 0
        )
      end

      let(:retirement_card) do
        {
          "id"         => "retirement_0",
          "card_type"  => "retirement",
          "heading"    => "Passage 1 — Existing pattern",
          "reason"     => "Superseded by a newer passage.",
          "passage_id" => passage.id,
          "decision"   => "accepted"
        }
      end

      before do
        create(:translation_job, :voice_calibration, :completed, novel: novel, user: user,
               result_payload: { cards: [ retirement_card ] }.to_json)
      end

      it "destroys the retired VoiceCalibrationPassage" do
        expect {
          post novel_voice_calibration_review_commit_path(novel)
        }.to change(novel.voice_calibration_passages, :count).by(-1)
      end

      it "removes the retired passage's block from voice_calibration.md" do
        post novel_voice_calibration_review_commit_path(novel)

        expect(File.read(doc_path)).not_to include("Passage 1 — Existing pattern")
      end
    end
  end
end
