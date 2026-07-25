require "rails_helper"

RSpec.describe Pipeline::Ruby::PrereadRunner::ChapterDiscovery do
  describe ".extract_chapter_number" do
    it "returns the first integer found in a filename" do
      expect(described_class.extract_chapter_number("ch12_korean")).to eq(12)
      expect(described_class.extract_chapter_number("Chapter 74.txt")).to eq(74)
    end

    it "returns nil when the filename has no digits" do
      expect(described_class.extract_chapter_number("no_number_here.txt")).to be_nil
    end
  end

  describe "chapter file discovery" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    def touch(*names)
      names.each { |n| File.write(File.join(@dir, n), "content") }
    end

    it "finds all chapters with a korean source file" do
      touch("ch1_korean", "ch2_korean", "Chapter 1.txt")

      expect(described_class.find_all_korean_chapters(@dir)).to eq([ 1, 2 ])
    end

    it "finds translated chapter numbers, excluding korean sources and reference translations" do
      touch("ch1_korean", "Chapter 1.txt", "Chapter 2.txt", "Chapter 3 (another translation).txt")

      expect(described_class.find_translated_chapter_numbers(@dir)).to eq(Set.new([ 1, 2 ]))
    end

    it "finds untranslated chapters as korean-source-present minus already-translated" do
      touch("ch1_korean", "Chapter 1.txt", "ch2_korean", "ch3_korean")

      expect(described_class.find_untranslated_chapters(@dir)).to eq([ 2, 3 ])
    end
  end

  describe ".filter_to_available" do
    it "keeps only requested numbers present in the available set, sorted and deduped" do
      result = described_class.filter_to_available([ 5, 3, 3, 1 ], Set.new([ 1, 3 ]))

      expect(result.selected).to eq([ 1, 3 ])
      expect(result.skipped).to eq([ 5 ])
    end

    it "reports no skips when every requested number is available" do
      result = described_class.filter_to_available([ 1, 2 ], Set.new([ 1, 2 ]))

      expect(result.selected).to eq([ 1, 2 ])
      expect(result.skipped).to eq([])
    end
  end
end
