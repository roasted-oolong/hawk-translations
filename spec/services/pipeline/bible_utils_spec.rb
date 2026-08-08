require "rails_helper"

RSpec.describe Pipeline::BibleUtils do
  describe ".heading_key" do
    it "uses the Korean parenthetical as the key when present" do
      expect(described_class.heading_key("Hee-yeon Lee (이희연) — English")).to eq("이희연")
      expect(described_class.heading_key("LOAN (로안) — English")).to eq("로안")
    end

    it "derives the same key for different English romanisations of the same Korean name" do
      expect(described_class.heading_key("LOAN (로안) — English")).to eq(
        described_class.heading_key("Ro-an (로안) — English")
      )
    end

    it "falls back to normalised English text with no Korean parenthetical" do
      expect(described_class.heading_key("SM Entertainment — English")).to eq("sm entertainment")
      expect(described_class.heading_key("Debut — English")).to eq("debut")
    end

    it "drops parentheticals with no Korean characters from the English fallback" do
      expect(described_class.heading_key("Debut (formal) — English")).to eq("debut")
    end
  end

  describe ".normalize_korean" do
    it "collapses runs of internal whitespace to a single space" do
      expect(described_class.normalize_korean("김민준   에게")).to eq("김민준 에게")
    end

    it "strips leading/trailing whitespace" do
      expect(described_class.normalize_korean("  영석  ")).to eq("영석")
    end

    it "downcases Latin-script terms without affecting Hangul" do
      expect(described_class.normalize_korean("SM Entertainment")).to eq("sm entertainment")
      expect(described_class.normalize_korean("영석")).to eq("영석")
    end

    it "unicode-normalises so full-width and half-width forms match" do
      expect(described_class.normalize_korean("ＳＭ")).to eq(described_class.normalize_korean("SM").downcase)
    end

    it "is nil-safe" do
      expect(described_class.normalize_korean(nil)).to eq("")
    end
  end

  describe ".extract_heading_keys" do
    it "returns one key per ## heading in the text" do
      text = <<~MD
        ## Hee-yeon Lee (이희연) — English
        - Role: protagonist

        ## SM Entertainment — English
        - Notes: agency
      MD

      expect(described_class.extract_heading_keys(text)).to eq(Set.new(%w[이희연] + [ "sm entertainment" ]))
    end

    it "returns an empty set for text with no ## headings" do
      expect(described_class.extract_heading_keys("plain prose, no headings")).to eq(Set.new)
    end
  end
end
