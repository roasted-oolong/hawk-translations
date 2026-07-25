require "rails_helper"

RSpec.describe Pipeline::BibleReviewWriter do
  around do |example|
    Dir.mktmpdir do |dir|
      @novel_dir = dir
      FileUtils.mkdir_p(File.join(dir, "bible"))
      example.run
    end
  end

  def write_bible(relative, content)
    File.write(File.join(@novel_dir, relative), content)
  end

  def read_bible(relative)
    File.read(File.join(@novel_dir, relative))
  end

  subject(:writer) { described_class.new(@novel_dir) }

  describe "#commit for proposed_edit cards" do
    before { write_bible("bible/characters.md", "## Existing Char (기존) — English\n- Role: villager\n") }

    it "applies the edit when current text matches exactly once" do
      card = { "card_type" => "proposed_edit", "section_key" => "characters",
               "current" => "- Role: villager", "proposed" => "- Role: idol trainee" }

      expect(writer.commit(card)).to eq(:applied)
      expect(read_bible("bible/characters.md")).to include("- Role: idol trainee")
    end

    it "skips with :skipped_not_found when the current text is no longer present (stale card)" do
      card = { "card_type" => "proposed_edit", "section_key" => "characters",
               "current" => "- Role: no longer here", "proposed" => "x" }

      expect(writer.commit(card)).to eq(:skipped_not_found)
      expect(read_bible("bible/characters.md")).to include("- Role: villager")
    end

    it "skips with :skipped_ambiguous when the current text matches more than once" do
      write_bible("bible/characters.md", "- Role: villager\n- Role: villager\n")
      card = { "card_type" => "proposed_edit", "section_key" => "characters",
               "current" => "- Role: villager", "proposed" => "x" }

      expect(writer.commit(card)).to eq(:skipped_ambiguous)
    end

    it "skips with :skipped_unresolved_file when section_key doesn't map to a known bible file" do
      card = { "card_type" => "proposed_edit", "section_key" => "not_a_real_section",
               "current" => "x", "proposed" => "y" }

      expect(writer.commit(card)).to eq(:skipped_unresolved_file)
    end

    it "re-validates against a fresh read, not a stale snapshot the card was built from" do
      # Simulates the bible changing between proposal generation and commit —
      # the "current" text from the original snapshot no longer exists.
      write_bible("bible/characters.md", "## Existing Char (기존) — English\n- Role: changed already\n")
      card = { "card_type" => "proposed_edit", "section_key" => "characters",
               "current" => "- Role: villager", "proposed" => "- Role: idol trainee" }

      expect(writer.commit(card)).to eq(:skipped_not_found)
    end
  end

  describe "#commit for new_entry cards" do
    before { write_bible("bible/characters.md", "## Existing Char (기존) — English\n- Role: villager\n") }

    it "appends a new entry" do
      card = { "card_type" => "new_entry", "section_key" => "characters",
               "content" => "## New Girl (새아이) — English\n- Role: rival\n" }

      expect(writer.commit(card)).to eq(:applied)
      expect(read_bible("bible/characters.md")).to include("New Girl")
    end

    it "dedups by heading key against the freshly-read file, not the card's own snapshot" do
      card = { "card_type" => "new_entry", "section_key" => "characters",
               "content" => "## Existing Char (기존) — English\n- Role: villager\n" }

      expect(writer.commit(card)).to eq(:skipped_duplicate)
    end

    it "matches duplicates across different English romanisations via the shared Korean parenthetical" do
      card = { "card_type" => "new_entry", "section_key" => "characters",
               "content" => "## Different Romanisation (기존) — English\n- Role: villager\n" }

      expect(writer.commit(card)).to eq(:skipped_duplicate)
    end

    it "rerunning the same accepted card twice is idempotent — no duplicate written" do
      card = { "card_type" => "new_entry", "section_key" => "characters",
               "content" => "## New Girl (새아이) — English\n- Role: rival\n" }

      expect(writer.commit(card)).to eq(:applied)
      expect(writer.commit(card)).to eq(:skipped_duplicate)
      expect(read_bible("bible/characters.md").scan("New Girl").length).to eq(1)
    end
  end

  describe "#commit for story_update cards" do
    before { write_bible("bible/story.md", "## Open Arcs\n- Debut arc in motion\n") }

    it "appends the formatted update to story.md" do
      card = { "card_type" => "story_update", "type" => "Main Plot", "update" => "Min-jun decided to audition." }

      expect(writer.commit(card)).to eq(:applied)
      expect(read_bible("bible/story.md")).to include("**Main Plot** — Min-jun decided to audition.")
    end

    it "dedups by exact text match against the freshly-read file" do
      write_bible("bible/story.md", "## Open Arcs\n\n---\n\n**Main Plot** — Min-jun decided to audition.\n")
      card = { "card_type" => "story_update", "type" => "Main Plot", "update" => "Min-jun decided to audition." }

      expect(writer.commit(card)).to eq(:skipped_duplicate)
    end
  end

  it "returns :skipped_unknown_card_type for an unrecognised card_type" do
    expect(writer.commit({ "card_type" => "something_else" })).to eq(:skipped_unknown_card_type)
  end

  describe "atomic write behavior (delegated to Pipeline::BibleFileEditor)" do
    it "never leaves a stray .tmp file behind after a successful write" do
      write_bible("bible/characters.md", "")
      card = { "card_type" => "new_entry", "section_key" => "characters", "content" => "## Entry\n- Role: x\n" }

      writer.commit(card)

      expect(File.exist?(File.join(@novel_dir, "bible/characters.md.tmp"))).to eq(false)
    end
  end

  describe "concurrent writers to the same bible file" do
    it "serializes two concurrent commits so neither write is lost" do
      write_bible("bible/characters.md", "")
      barrier = Queue.new

      threads = 2.times.map do |i|
        Thread.new do
          barrier.pop
          described_class.new(@novel_dir).commit(
            "card_type" => "new_entry", "section_key" => "characters",
            "content" => "## Entry #{i} (엔트리#{i}) — English\n- Role: x\n"
          )
        end
      end
      2.times { barrier << :go }
      threads.each(&:join)

      content = read_bible("bible/characters.md")
      expect(content).to include("Entry 0")
      expect(content).to include("Entry 1")
    end
  end
end
