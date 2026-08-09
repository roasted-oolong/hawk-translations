require "rails_helper"

RSpec.describe RenderingRuleDocWriter do
  around do |example|
    Dir.mktmpdir do |dir|
      @novel_dir = dir
      example.run
    end
  end

  def guide_path
    File.join(@novel_dir, "bible/rendering_guide.md")
  end

  def read_guide
    File.read(guide_path)
  end

  def rule(name:, guidance:, example_input: nil, example_output: nil)
    RenderingRule.new(name: name, guidance: guidance,
                       example_input: example_input, example_output: example_output)
  end

  subject(:writer) { described_class.new(@novel_dir) }

  describe "#write" do
    it "creates the bible directory if it doesn't exist yet" do
      writer.write([ rule(name: "Dialogue", guidance: "Use double quotes.") ])
      expect(File.directory?(File.join(@novel_dir, "bible"))).to be true
    end

    it "writes each rule's name and guidance" do
      writer.write([ rule(name: "Dialogue", guidance: "Use double quotes.") ])
      expect(read_guide).to include("## Dialogue")
      expect(read_guide).to include("Use double quotes.")
    end

    it "includes the worked example when present" do
      writer.write([ rule(name: "Dialogue", guidance: "Use double quotes.",
                           example_input: "그가 말했다.", example_output: "he said.") ])
      expect(read_guide).to include("그가 말했다.")
      expect(read_guide).to include("he said.")
    end

    it "omits the example block when neither example field is present" do
      writer.write([ rule(name: "Dialogue", guidance: "Use double quotes.") ])
      expect(read_guide).not_to include("Example:")
    end

    it "includes the example block when only one side is present" do
      writer.write([ rule(name: "Dialogue", guidance: "Use double quotes.", example_input: "그가 말했다.") ])
      expect(read_guide).to include("Example:")
      expect(read_guide).to include("그가 말했다.")
    end

    it "writes multiple rules in the given order" do
      writer.write([
        rule(name: "Dialogue", guidance: "First."),
        rule(name: "Thoughts", guidance: "Second.")
      ])
      expect(read_guide.index("## Dialogue")).to be < read_guide.index("## Thoughts")
    end

    it "fully overwrites stale content from a previous write rather than appending" do
      writer.write([ rule(name: "Dialogue", guidance: "Old rule.") ])
      writer.write([ rule(name: "Thoughts", guidance: "New rule.") ])
      expect(read_guide).not_to include("Dialogue")
      expect(read_guide).not_to include("Old rule.")
      expect(read_guide).to include("Thoughts")
    end

    it "removes an existing file when given no rules" do
      writer.write([ rule(name: "Dialogue", guidance: "Use double quotes.") ])
      writer.write([])
      expect(File.exist?(guide_path)).to be false
    end

    it "is a no-op when given no rules and no file exists yet" do
      expect { writer.write([]) }.not_to raise_error
      expect(File.exist?(guide_path)).to be false
    end

    it "does not raise when novel_dir is blank" do
      expect { described_class.new(nil).write([ rule(name: "Dialogue", guidance: "x") ]) }.not_to raise_error
      expect { described_class.new("").write([ rule(name: "Dialogue", guidance: "x") ]) }.not_to raise_error
    end
  end
end
