require "rails_helper"

RSpec.describe Pipeline::TranslatedChapterReader do
  around do |example|
    Dir.mktmpdir do |dir|
      @chapters_dir = dir
      example.run
    end
  end

  def write_chapter(name, content)
    File.write(File.join(@chapters_dir, name), content)
  end

  describe ".read" do
    it "reads the translated .txt file matching the chapter number" do
      write_chapter("Chapter 5.txt", "translated text")
      expect(described_class.read(@chapters_dir, 5)).to eq("translated text")
    end

    it "skips korean source files" do
      write_chapter("ch5_korean.txt", "korean text")
      expect(described_class.read(@chapters_dir, 5)).to be_nil
    end

    it "skips reference translation files containing 'another translation'" do
      write_chapter("Chapter 5 another translation.txt", "reference text")
      expect(described_class.read(@chapters_dir, 5)).to be_nil
    end

    it "returns nil when no matching file exists" do
      expect(described_class.read(@chapters_dir, 99)).to be_nil
    end

    it "ignores non-.txt files" do
      write_chapter("Chapter 5.docx", "wrong format")
      expect(described_class.read(@chapters_dir, 5)).to be_nil
    end
  end
end
