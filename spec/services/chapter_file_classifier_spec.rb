# spec/services/chapter_file_classifier_spec.rb
#
# ChapterFileClassifier — given a file IO stream and a filename:
#   - Detects language from the first 4KB of content (Hangul ratio)
#   - Extracts chapter number from the filename (two patterns only)

require "rails_helper"

RSpec.describe ChapterFileClassifier do
  # Helpers to build an IO-like object the classifier can read
  def stream(content)
    StringIO.new(content)
  end

  def classify(content:, filename:)
    described_class.new(stream(content), filename).classify
  end

  # ---------------------------------------------------------------------------
  # Language detection — content is the authority; filename is irrelevant
  # ---------------------------------------------------------------------------
  describe "#classify — language detection" do
    context "when content is pure Korean (Hangul only)" do
      it "returns language: :korean" do
        korean = "가나다라마바사아자차카타파하" * 20
        result = classify(content: korean, filename: "anything.txt")
        expect(result[:language]).to eq(:korean)
      end
    end

    context "when content is pure English (ASCII only)" do
      it "returns language: :english" do
        english = "The quick brown fox jumps over the lazy dog." * 20
        result = classify(content: english, filename: "anything.txt")
        expect(result[:language]).to eq(:english)
      end
    end

    context "when content has no non-ASCII characters" do
      it "returns language: :english (no Hangul to detect)" do
        ascii_only = "Line one.\nLine two.\nLine three.\n"
        result = classify(content: ascii_only, filename: "anything.txt")
        expect(result[:language]).to eq(:english)
      end
    end

    context "when Hangul is more than 50% of non-ASCII, non-whitespace characters" do
      it "returns language: :korean" do
        # 60 Hangul + 40 non-ASCII non-Hangul (accented Latin)
        hangul     = "가" * 60
        non_hangul = "é" * 40
        result = classify(content: hangul + non_hangul, filename: "anything.txt")
        expect(result[:language]).to eq(:korean)
      end
    end

    context "when Hangul is exactly 50% of non-ASCII, non-whitespace characters" do
      it "returns language: :english (threshold is strictly > 50%)" do
        hangul     = "가" * 50
        non_hangul = "é" * 50
        result = classify(content: hangul + non_hangul, filename: "anything.txt")
        expect(result[:language]).to eq(:english)
      end
    end

    context "when Hangul is less than 50% of non-ASCII, non-whitespace characters" do
      it "returns language: :english" do
        hangul     = "가" * 40
        non_hangul = "é" * 60
        result = classify(content: hangul + non_hangul, filename: "anything.txt")
        expect(result[:language]).to eq(:english)
      end
    end

    context "when content is a realistic translated file quoting the original" do
      it "returns language: :english when Hangul is a minority" do
        # Translated output may quote Korean in footnotes; Hangul must stay minority
        english_body = ("The manager looked up from his desk. ") * 50
        hangul_quote = "가나다라마바사아자차"  # 10 Hangul chars
        result = classify(content: english_body + hangul_quote, filename: "Chapter 3.txt")
        expect(result[:language]).to eq(:english)
      end
    end

    context "when the file is larger than 4KB" do
      it "only samples the first 4096 bytes to detect language" do
        # First 4096 bytes are ASCII-only; remainder is pure Hangul.
        # Classifier reads only the sample, so it must return :english.
        english_prefix = "a" * 4096
        hangul_suffix  = "가" * 10_000
        result = classify(content: english_prefix + hangul_suffix, filename: "anything.txt")
        expect(result[:language]).to eq(:english)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Chapter number extraction — filename is the authority; content is irrelevant
  # ---------------------------------------------------------------------------
  describe "#classify — chapter number extraction" do
    # Use neutral Korean content so language never influences number tests
    let(:korean_content) { "가나다라" * 100 }

    context "with N화 pattern" do
      it "extracts the number from '3화.txt'" do
        result = classify(content: korean_content, filename: "3화.txt")
        expect(result[:chapter_number]).to eq(3)
      end

      it "extracts the number from '제3화.txt' (Korean ordinal prefix)" do
        result = classify(content: korean_content, filename: "제3화.txt")
        expect(result[:chapter_number]).to eq(3)
      end

      it "extracts the number from a filename with extra text before 화" do
        result = classify(content: korean_content, filename: "소설_10화_원고.txt")
        expect(result[:chapter_number]).to eq(10)
      end
    end

    context "with 'Chapter N' pattern" do
      it "extracts the number from 'Chapter 3.txt'" do
        result = classify(content: korean_content, filename: "Chapter 3.txt")
        expect(result[:chapter_number]).to eq(3)
      end

      it "extracts the number from 'Chapter 3 - Some Title.txt'" do
        result = classify(content: korean_content, filename: "Chapter 3 - Some Title.txt")
        expect(result[:chapter_number]).to eq(3)
      end

      it "extracts the number from 'chapter 3.txt' (lowercase — case-insensitive)" do
        result = classify(content: korean_content, filename: "chapter 3.txt")
        expect(result[:chapter_number]).to eq(3)
      end

      it "extracts the number from 'CHAPTER 74.txt' (all caps)" do
        result = classify(content: korean_content, filename: "CHAPTER 74.txt")
        expect(result[:chapter_number]).to eq(74)
      end
    end

    context "when 화 pattern appears before 'Chapter N' in the same filename" do
      it "returns the 화 match (화 pattern is tried first)" do
        result = classify(content: korean_content, filename: "Chapter 5 — 5화.txt")
        expect(result[:chapter_number]).to eq(5)
      end
    end

    context "when filename does not match any recognised pattern" do
      it "returns nil for 'notes.txt'" do
        result = classify(content: korean_content, filename: "notes.txt")
        expect(result[:chapter_number]).to be_nil
      end

      it "returns nil for a bare integer filename like '3.txt'" do
        result = classify(content: korean_content, filename: "3.txt")
        expect(result[:chapter_number]).to be_nil
      end

      it "returns nil for 'ep3.txt' (unrecognised prefix)" do
        result = classify(content: korean_content, filename: "ep3.txt")
        expect(result[:chapter_number]).to be_nil
      end

      it "returns nil for 'ch10_korean' (old convention — no longer recognised)" do
        result = classify(content: korean_content, filename: "ch10_korean")
        expect(result[:chapter_number]).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Return shape
  # ---------------------------------------------------------------------------
  describe "#classify — return value" do
    it "always returns a hash with :language and :chapter_number keys" do
      result = described_class.new(stream("hello"), "notes.txt").classify
      expect(result).to include(:language, :chapter_number)
    end

    it ":language is always :korean or :english" do
      result = described_class.new(stream("가나다"), "notes.txt").classify
      expect(result[:language]).to be_in(%i[korean english])
    end
  end
end
