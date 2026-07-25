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
