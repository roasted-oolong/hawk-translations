require "rails_helper"

RSpec.describe Pipeline::PromptUtils do
  describe ".empty?" do
    it "treats nil, blank, and whitespace-only content as empty" do
      expect(described_class.empty?(nil)).to eq(true)
      expect(described_class.empty?("")).to eq(true)
      expect(described_class.empty?("   \n  ")).to eq(true)
    end

    it "treats content containing only template markers as empty" do
      expect(described_class.empty?("## [Character Name — English]\n- Korean name: ")).to eq(true)
      expect(described_class.empty?("## [Term — English]\n- Korean term: ")).to eq(true)
      expect(described_class.empty?("## [Phrase — English]\n- Korean phrase: ")).to eq(true)
      expect(described_class.empty?("## [Korean phrase]\n- Literal translation: ")).to eq(true)
      expect(described_class.empty?("## [Location Name — English]\n- Korean name: ")).to eq(true)
      expect(described_class.empty?("Current summary: \n- Key turning points:\n")).to eq(true)
    end

    it "treats real populated content as not empty" do
      expect(described_class.empty?("## Hee-yeon Lee (이희연) — English\n- Role: protagonist")).to eq(false)
    end
  end

  describe ".section" do
    it "returns an empty string when the content is empty" do
      expect(described_class.section("Characters", "")).to eq("")
      expect(described_class.section("Characters", "## [Character Name — English]\n")).to eq("")
    end

    it "formats a populated section with a heading and stripped content" do
      result = described_class.section("Characters", "  ## Hee-yeon Lee\n- Role: protagonist  \n")
      expect(result).to eq("## Characters\n\n## Hee-yeon Lee\n- Role: protagonist\n")
    end
  end
end
