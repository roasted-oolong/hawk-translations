require "rails_helper"

RSpec.describe TranslationJob, type: :model do
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  describe "associations" do
    it "belongs to a novel" do
      novel = create(:novel)
      user  = create(:user)
      job   = create(:translation_job, novel: novel, user: user)
      expect(job.novel).to eq(novel)
    end

    it "belongs to a user" do
      novel = create(:novel)
      user  = create(:user)
      job   = create(:translation_job, novel: novel, user: user)
      expect(job.user).to eq(user)
    end
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  describe "validations" do
    it "is valid with all required attributes" do
      job = build(:translation_job)
      expect(job).to be_valid
    end

    it "requires job_type" do
      job = build(:translation_job, job_type: nil)
      expect(job).not_to be_valid
      expect(job.errors[:job_type]).to be_present
    end

    it "requires status" do
      job = TranslationJob.new(
        novel:         create(:novel),
        user:          create(:user),
        job_type:      "preread",
        chapter_start: 1,
        chapter_end:   5
      )
      # Bypass enum assignment so we can test the presence validation directly
      job.write_attribute(:status, nil)
      expect(job).not_to be_valid
      expect(job.errors[:status]).to be_present
    end

    describe "chapter range consistency" do
      it "is valid for bible_build when chapter_start and chapter_end are present" do
        job = build(:translation_job, :bible_build)
        expect(job).to be_valid
      end

      it "is invalid when both chapter_start and chapter_end are nil" do
        job = build(:translation_job, chapter_start: nil, chapter_end: nil)
        expect(job).not_to be_valid
        expect(job.errors[:chapter_start]).to be_present
      end

      it "is valid when chapter_start equals chapter_end (single chapter)" do
        job = build(:translation_job, :post_translation_review,
                    chapter_start: 5, chapter_end: 5)
        expect(job).to be_valid
      end

      it "is valid when chapter_start is less than chapter_end (range)" do
        job = build(:translation_job, job_type: "preread",
                    chapter_start: 1, chapter_end: 10)
        expect(job).to be_valid
      end

      it "is invalid when chapter_start is present but chapter_end is nil" do
        job = build(:translation_job, chapter_start: 1, chapter_end: nil)
        expect(job).not_to be_valid
        expect(job.errors[:chapter_end]).to be_present
      end

      it "is invalid when chapter_end is present but chapter_start is nil" do
        job = build(:translation_job, chapter_start: nil, chapter_end: 5)
        expect(job).not_to be_valid
        expect(job.errors[:chapter_start]).to be_present
      end

      it "is invalid when chapter_start is greater than chapter_end" do
        job = build(:translation_job, chapter_start: 10, chapter_end: 5)
        expect(job).not_to be_valid
        expect(job.errors[:chapter_start]).to be_present
      end

      it "is invalid when chapter_start is not a positive integer" do
        job = build(:translation_job, chapter_start: 0, chapter_end: 5)
        expect(job).not_to be_valid
        expect(job.errors[:chapter_start]).to be_present
      end
    end

    describe "chapter_bible_proposals_resolved (translate_batch only)" do
      it "is invalid when a chapter in the job's own range has an unresolved bible proposal" do
        novel   = create(:novel)
        chapter = create(:chapter, novel: novel, number: 1)
        create(:bible_entry_proposal, novel: novel, chapter: chapter)

        job = build(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

        expect(job).not_to be_valid
        expect(job.errors[:chapter_start]).to be_present
      end

      it "is valid when every chapter in range has no unresolved proposals" do
        novel = create(:novel)
        create(:chapter, novel: novel, number: 1)

        job = build(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

        expect(job).to be_valid
      end

      it "a fully-reviewed chapter 77 does not unlock chapter 76's own unresolved proposals" do
        novel      = create(:novel)
        chapter76  = create(:chapter, novel: novel, number: 76)
        create(:chapter, novel: novel, number: 77)
        create(:bible_entry_proposal, novel: novel, chapter: chapter76)

        job_76 = build(:translation_job, :translate_batch, novel: novel, chapter_start: 76, chapter_end: 76)
        job_77 = build(:translation_job, :translate_batch, novel: novel, chapter_start: 77, chapter_end: 77)

        expect(job_76).not_to be_valid
        expect(job_77).to be_valid
      end

      it "checks the translate job's own range, not the range the proposal's own chapter falls outside of" do
        novel      = create(:novel)
        chapter5   = create(:chapter, novel: novel, number: 5)
        create(:chapter, novel: novel, number: 10)
        create(:bible_entry_proposal, novel: novel, chapter: chapter5)

        job = build(:translation_job, :translate_batch, novel: novel, chapter_start: 10, chapter_end: 10)

        expect(job).to be_valid
      end

      it "does not apply to non-translate_batch job types" do
        novel   = create(:novel)
        chapter = create(:chapter, novel: novel, number: 1)
        create(:bible_entry_proposal, novel: novel, chapter: chapter)

        job = build(:translation_job, job_type: "preread", novel: novel, chapter_start: 1, chapter_end: 1)

        expect(job).to be_valid
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  describe "enums" do
    describe "job_type" do
      it "accepts preread" do
        job = build(:translation_job, job_type: "preread")
        expect(job.preread?).to be true
      end

      it "accepts bible_build" do
        job = build(:translation_job, job_type: "bible_build")
        expect(job.bible_build?).to be true
      end

      it "accepts post_translation_review" do
        job = build(:translation_job, job_type: "post_translation_review")
        expect(job.post_translation_review?).to be true
      end

      it "raises on unknown job_type" do
        expect {
          build(:translation_job, job_type: "unknown")
        }.to raise_error(ArgumentError)
      end
    end

    describe "status" do
      it "accepts queued" do
        job = build(:translation_job, status: "queued")
        expect(job.queued?).to be true
      end

      it "accepts running" do
        job = build(:translation_job, status: "running")
        expect(job.running?).to be true
      end

      it "accepts completed" do
        job = build(:translation_job, status: "completed")
        expect(job.completed?).to be true
      end

      it "accepts failed" do
        job = build(:translation_job, status: "failed")
        expect(job.failed?).to be true
      end

      it "raises on unknown status" do
        expect {
          build(:translation_job, status: "unknown")
        }.to raise_error(ArgumentError)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  describe "scopes" do
    let(:novel) { create(:novel) }
    let(:user)  { create(:user) }

    describe ".recent" do
      it "orders by created_at descending" do
        older = create(:translation_job, novel: novel, user: user,
                       created_at: 2.hours.ago)
        newer = create(:translation_job, novel: novel, user: user,
                       created_at: 1.hour.ago)
        expect(TranslationJob.recent.to_a).to eq([ newer, older ])
      end
    end

    describe ".for_novel" do
      it "returns only jobs belonging to the given novel" do
        other_novel = create(:novel)
        job         = create(:translation_job, novel: novel, user: user)
        _other_job  = create(:translation_job, novel: other_novel, user: user)
        expect(TranslationJob.for_novel(novel).to_a).to eq([ job ])
      end
    end

    describe ".cancellable" do
      it "returns queued and running jobs" do
        queued    = create(:translation_job, :queued, novel: novel, user: user)
        running   = create(:translation_job, :running, novel: novel, user: user)
        create(:translation_job, :completed, novel: novel, user: user)
        create(:translation_job, :failed, novel: novel, user: user)

        expect(described_class.cancellable).to contain_exactly(queued, running)
      end
    end

  end

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------
  describe "#chapter_range_label" do
    it "returns a range for a bible_build job" do
      job = build(:translation_job, :bible_build)
      expect(job.chapter_range_label).to eq("Chapters 1\u201374")
    end

    it "returns nil when both chapter_start and chapter_end are nil (defensive)" do
      job = build(:translation_job, chapter_start: nil, chapter_end: nil)
      expect(job.chapter_range_label).to be_nil
    end

    it "returns a single chapter number when start equals end" do
      job = build(:translation_job, chapter_start: 5, chapter_end: 5)
      expect(job.chapter_range_label).to eq("Chapter 5")
    end

    it "returns a range when start and end differ" do
      job = build(:translation_job, chapter_start: 1, chapter_end: 10)
      expect(job.chapter_range_label).to eq("Chapters 1\u201310")
    end
  end

  describe "#cancellable?" do
    it "returns true when status is queued" do
      job = build(:translation_job, status: "queued")
      expect(job.cancellable?).to be true
    end

    it "returns true when status is running" do
      job = build(:translation_job, status: "running")
      expect(job.cancellable?).to be true
    end

    it "returns false when status is completed" do
      job = build(:translation_job, status: "completed")
      expect(job.cancellable?).to be false
    end

    it "returns false when status is failed" do
      job = build(:translation_job, status: "failed")
      expect(job.cancellable?).to be false
    end
  end

  describe "#result_summary" do
    it "extracts the summary field from a translate_batch JSON payload" do
      job = build(:translation_job, :translate_batch,
                  result_payload: { summary: "2 chapter(s) translated.", chapters: {} }.to_json)
      expect(job.result_summary).to eq("2 chapter(s) translated.")
    end

    it "falls back to the raw payload when a translate_batch payload isn't valid JSON" do
      job = build(:translation_job, :translate_batch, result_payload: "not json at all")
      expect(job.result_summary).to eq("not json at all")
    end

    it "falls back to the raw payload when translate_batch JSON has no summary key" do
      job = build(:translation_job, :translate_batch, result_payload: { chapters: {} }.to_json)
      expect(job.result_summary).to eq({ chapters: {} }.to_json)
    end

    it "passes non-translate_batch job types through unchanged" do
      job = build(:translation_job, job_type: "preread", result_payload: "plain text output")
      expect(job.result_summary).to eq("plain text output")
    end
  end

  describe "#mark_dead!" do
    let(:novel) { create(:novel) }
    let(:user)  { create(:user) }

    it "marks the job failed and records the reason" do
      job = create(:translation_job, :running, novel: novel, user: user)

      job.mark_dead!("Worker process died.")

      expect(job.reload.status).to eq("failed")
      expect(job.result_payload).to eq("Worker process died.")
    end

    it "resets prereading chapters to preread_failed for preread jobs" do
      create(:chapter, novel: novel, number: 1, status: "prereading")
      create(:chapter, novel: novel, number: 2, status: "preread")
      job = create(:translation_job, :running, novel: novel, user: user,
                   job_type: "preread", chapter_start: 1, chapter_end: 2)

      job.mark_dead!("Worker process died.")

      expect(novel.chapters.find_by(number: 1).status).to eq("preread_failed")
      expect(novel.chapters.find_by(number: 2).status).to eq("preread")
    end

    it "does not touch chapters for non-preread jobs" do
      create(:chapter, novel: novel, number: 1, status: "prereading")
      job = create(:translation_job, :running, novel: novel, user: user,
                   job_type: "translate_batch", chapter_start: 1, chapter_end: 1)

      job.mark_dead!("Worker process died.")

      expect(novel.chapters.find_by(number: 1).status).to eq("prereading")
    end
  end

  describe "#broadcast_preread_entries_status" do
    let(:novel) { create(:novel) }
    let(:user)  { create(:user) }

    def capture_broadcasts(job)
      calls = []
      allow(job).to receive(:broadcast_replace_later_to) { |target, **kwargs| calls << [ target, kwargs ] }
      allow(job).to receive(:broadcast_remove_to)
      yield
      calls
    end

    it "broadcasts a replace to the novel's preread stream on a preread job's status change" do
      job = create(:translation_job, :queued, novel: novel, user: user, job_type: "preread")

      calls = capture_broadcasts(job) { job.update!(status: "running") }

      expect(calls.map(&:first)).to include("novel_#{novel.id}_preread")
    end

    it "does not broadcast to the preread stream for non-preread job types" do
      job = create(:translation_job, :queued, novel: novel, user: user,
                   job_type: "translate_batch", chapter_start: 1, chapter_end: 1)

      calls = capture_broadcasts(job) { job.update!(status: "running") }

      expect(calls.map(&:first)).not_to include("novel_#{novel.id}_preread")
    end

    it "targets the preread-entries-status element with the shared partial" do
      job = create(:translation_job, :queued, novel: novel, user: user, job_type: "preread")

      calls = capture_broadcasts(job) { job.update!(status: "running") }

      _target, kwargs = calls.find { |(target, _)| target == "novel_#{novel.id}_preread" }
      expect(kwargs[:target]).to eq("preread-entries-status")
      expect(kwargs[:partial]).to eq("chapter_review/preread_entries_status")
      expect(kwargs[:locals][:novel]).to eq(novel)
    end

    it "counts bible_entry_proposals for pending_count/pending_breakdown, not the bible files" do
      chapter = create(:chapter, novel: novel)
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character", korean_key: "a")
      job = create(:translation_job, :queued, novel: novel, user: user, job_type: "preread")

      calls = capture_broadcasts(job) { job.update!(status: "running") }

      _target, kwargs = calls.find { |(target, _)| target == "novel_#{novel.id}_preread" }
      expect(kwargs[:locals][:pending_count]).to eq(1)
      expect(kwargs[:locals][:pending_breakdown]).to eq("character" => 1)
    end
  end
end
