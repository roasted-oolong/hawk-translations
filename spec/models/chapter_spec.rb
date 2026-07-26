require "rails_helper"

RSpec.describe Chapter, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      chapter = build(:chapter)
      expect(chapter).to be_valid
    end

    it "requires novel" do
      chapter = build(:chapter, novel: nil)
      expect(chapter).not_to be_valid
      expect(chapter.errors[:novel]).to be_present
    end

    it "requires number" do
      chapter = build(:chapter, number: nil)
      expect(chapter).not_to be_valid
      expect(chapter.errors[:number]).to be_present
    end

    it "requires number to be a positive integer" do
      chapter = build(:chapter, number: 0)
      expect(chapter).not_to be_valid

      chapter = build(:chapter, number: -1)
      expect(chapter).not_to be_valid
    end

    it "requires number to be unique within a novel" do
      existing = create(:chapter, number: 1)
      duplicate = build(:chapter, novel: existing.novel, number: 1)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:number]).to be_present
    end

    it "allows the same number across different novels" do
      create(:chapter, number: 1)
      other_novel = create(:novel)
      chapter = build(:chapter, novel: other_novel, number: 1)
      expect(chapter).to be_valid
    end

    it "requires status" do
      chapter = build(:chapter, status: nil)
      expect(chapter).not_to be_valid
      expect(chapter.errors[:status]).to be_present
    end

    it "rejects an invalid status value" do
      expect {
        build(:chapter, status: "published")
      }.to raise_error(ArgumentError)
    end

    it "defaults status to untranslated" do
      chapter = create(:chapter)
      expect(chapter.status).to eq("untranslated")
    end
  end

  describe "enums" do
    it "accepts untranslated status" do
      chapter = build(:chapter, status: "untranslated")
      expect(chapter).to be_valid
    end

    it "accepts translated status" do
      chapter = build(:chapter, status: "translated")
      expect(chapter).to be_valid
    end

    it "accepts reviewed status" do
      chapter = build(:chapter, status: "reviewed")
      expect(chapter).to be_valid
    end

    it "accepts ocr_failed status" do
      chapter = build(:chapter, status: "ocr_failed")
      expect(chapter).to be_valid
    end

    it "accepts ocr_processing status" do
      chapter = build(:chapter, status: "ocr_processing")
      expect(chapter).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a novel" do
      novel = create(:novel)
      chapter = create(:chapter, novel: novel)
      expect(chapter.novel).to eq(novel)
    end

    it "has an optional title" do
      chapter = create(:chapter, title: nil)
      expect(chapter.title).to be_nil
    end

    it "stores a title when provided" do
      chapter = create(:chapter, title: "The Super Manager's Regression")
      expect(chapter.title).to eq("The Super Manager's Regression")
    end
  end

  describe "scopes" do
    it "orders by number ascending with .by_number" do
      novel = create(:novel)
      ch3   = create(:chapter, novel: novel, number: 3)
      ch1   = create(:chapter, novel: novel, number: 1)
      ch2   = create(:chapter, novel: novel, number: 2)
      expect(novel.chapters.by_number).to eq([ ch1, ch2, ch3 ])
    end
  end

  describe "Active Storage attachments" do
    it "accepts a korean_source attachment" do
      chapter = create(:chapter)
      chapter.korean_source.attach(
        io: StringIO.new("korean content"),
        filename: "ch1_korean",
        content_type: "text/plain"
      )
      expect(chapter.korean_source).to be_attached
    end

    it "accepts a translated_output attachment" do
      chapter = create(:chapter)
      chapter.translated_output.attach(
        io: StringIO.new("translated content"),
        filename: "Chapter_1.txt",
        content_type: "text/plain"
      )
      expect(chapter.translated_output).to be_attached
    end
  end

  describe "on destroy" do
    let(:novel_dir) { Dir.mktmpdir }
    let(:novel)     { create(:novel, directory_name: File.basename(novel_dir)) }
    let(:chapter)   { create(:chapter, novel: novel, number: 5) }
    let(:korean_path)     { File.join(novel_dir, "chapters", "Chapter 5 (Korean).txt") }
    let(:translated_path) { File.join(novel_dir, "chapters", "Chapter 5.txt") }

    before do
      @orig_root = ENV["HAWK_PROJECT_ROOT"]
      ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)
    end

    after do
      ENV["HAWK_PROJECT_ROOT"] = @orig_root
      FileUtils.rm_rf(novel_dir)
    end

    it "deletes the chapter's on-disk Korean source and translated output files" do
      chapter.korean_source.attach(io: StringIO.new("korean"), filename: "x.txt", content_type: "text/plain")
      KoreanSourceDiskWriter.new(novel).write(chapter)
      ChapterDiskWriter.new(novel).write(chapter, "translated")

      expect(File).to exist(korean_path)
      expect(File).to exist(translated_path)

      chapter.destroy

      expect(File).not_to exist(korean_path)
      expect(File).not_to exist(translated_path)
    end

    it "does not raise when no files exist on disk yet" do
      expect { chapter.destroy }.not_to raise_error
    end
  end
end
