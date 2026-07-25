require "rails_helper"

RSpec.describe Pipeline::PrereadBibleWriter do
  around do |example|
    Dir.mktmpdir do |dir|
      @novel_dir = dir
      FileUtils.mkdir_p(File.join(dir, "bible"))
      example.run
    end
  end

  subject(:writer) { described_class.new(@novel_dir) }

  def characters_path
    File.join(@novel_dir, "bible", "characters.md")
  end

  def story_path
    File.join(@novel_dir, "bible", "story.md")
  end

  it "writes a new entry to a bible file that doesn't exist yet, creating parent dirs" do
    status = writer.write_batch({ characters: "## Hee-yeon Lee (이희연) — English\n- Role: protagonist" })

    expect(status[:characters]).to eq(:written)
    expect(File.read(characters_path)).to eq("## Hee-yeon Lee (이희연) — English\n- Role: protagonist\n")
  end

  it "reports :empty and touches nothing for a section with blank content" do
    status = writer.write_batch({ characters: "", locations: "   " })

    expect(status[:characters]).to eq(:empty)
    expect(status[:locations]).to eq(:empty)
    expect(File.exist?(characters_path)).to eq(false)
  end

  it "deduplicates an entry whose heading key already exists in the file" do
    File.write(characters_path, "## LOAN (로안) — English\n- Role: rival\n")

    status = writer.write_batch({ characters: "## Ro-an (로안) — English\n- Role: updated rival" })

    expect(status[:characters]).to eq(:no_new_entries)
    expect(File.read(characters_path)).to eq("## LOAN (로안) — English\n- Role: rival\n")
  end

  it "appends only the genuinely new entries when a batch mixes new and duplicate headings" do
    File.write(characters_path, "## LOAN (로안) — English\n- Role: rival\n")
    batch = "## Ro-an (로안) — English\n- Role: updated\n\n## New Person (새인물) — English\n- Role: ally"

    status = writer.write_batch({ characters: batch })

    expect(status[:characters]).to eq(:written)
    content = File.read(characters_path)
    expect(content).to include("## LOAN (로안) — English\n- Role: rival")
    expect(content).to include("## New Person (새인물) — English\n- Role: ally")
    expect(content.scan("Role: rival").length).to eq(1)
  end

  it "uses a --- separator only when the file already has content" do
    File.write(characters_path, "## Existing (기존) — English\n- Role: x\n")

    writer.write_batch({ characters: "## New (신규) — English\n- Role: y" })

    expect(File.read(characters_path)).to include("\n\n---\n\n")
  end

  it "always includes plain-prose content with no ## heading, never treating it as a duplicate" do
    File.write(story_path, "## Open Arcs\n- Arc one\n")

    writer.write_batch({ story: "Plain narrative update with no heading." })

    expect(File.read(story_path)).to include("Plain narrative update with no heading.")
  end
end
