require "rails_helper"

RSpec.describe Pipeline::Ruby::FormatterResponseParser do
  describe ".parse" do
    it "extracts each chapter's formatted text, stripped" do
      raw = "=== CHAPTER 1 ===\n  cleaned one  \n=== END CHAPTER 1 ===\n\n" \
            "=== CHAPTER 2 ===\ncleaned two\n=== END CHAPTER 2 ==="

      result = described_class.parse(raw, [ 1, 2 ])

      expect(result.chapters).to eq({ 1 => "cleaned one", 2 => "cleaned two" })
      expect(result.missing).to eq([])
    end

    it "reports a chapter absent from the response as missing, without raising" do
      raw = "=== CHAPTER 1 ===\ncleaned one\n=== END CHAPTER 1 ==="

      result = described_class.parse(raw, [ 1, 2 ])

      expect(result.chapters).to eq({ 1 => "cleaned one" })
      expect(result.missing).to eq([ 2 ])
    end

    it "treats a malformed/unclosed delimiter as absent from the result" do
      raw = "=== CHAPTER 1 ===\nno closing marker here"

      result = described_class.parse(raw, [ 1 ])

      expect(result.chapters).to eq({})
      expect(result.missing).to eq([ 1 ])
    end

    it "returns an empty chapters hash with no missing entries when nothing was expected" do
      result = described_class.parse("no markers at all", [])

      expect(result.chapters).to eq({})
      expect(result.missing).to eq([])
    end
  end
end
