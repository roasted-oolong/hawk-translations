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
      it "is valid when both chapter_start and chapter_end are nil" do
        job = build(:translation_job, :bible_build)
        expect(job).to be_valid
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
      it "returns only queued jobs" do
        queued   = create(:translation_job, novel: novel, user: user, status: "queued")
        _running = create(:translation_job, novel: novel, user: user, status: "running")
        _done    = create(:translation_job, novel: novel, user: user, status: "completed")
        expect(TranslationJob.cancellable.to_a).to eq([ queued ])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------
  describe "#chapter_range_label" do
    it "returns nil when both chapter_start and chapter_end are nil" do
      job = build(:translation_job, :bible_build)
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

    it "returns false when status is running" do
      job = build(:translation_job, status: "running")
      expect(job.cancellable?).to be false
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
end
