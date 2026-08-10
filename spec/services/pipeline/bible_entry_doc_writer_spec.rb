require "rails_helper"

# =============================================================================
# Pipeline::BibleEntryDocWriter spec
#
# Mirrors RenderingRuleDocWriter's own spec shape (tmpdir novel_dir,
# create/overwrite/delete-on-empty), plus the one guarantee this writer adds
# on top of that shape: round-tripping back through Pipeline::BibleEntryMatcher
# (the same parser the live preread ingestion path uses) must reproduce the
# same field values the DB record actually has — that's the whole point of
# Part 3 (docs/PREREAD_STAGING_DESIGN.md) existing at all.
# =============================================================================
RSpec.describe Pipeline::BibleEntryDocWriter do
  around do |example|
    Dir.mktmpdir do |dir|
      @novel_dir = dir
      example.run
    end
  end

  let(:novel) { create(:novel, directory_name: File.basename(@novel_dir)) }

  def read_file(relative)
    File.read(File.join(@novel_dir, "bible", relative))
  end

  def file_path(relative)
    File.join(@novel_dir, "bible", relative)
  end

  # Round-trips a just-written category file back through the matcher and
  # asserts no field_changes are detected against the given record — i.e.
  # the file the writer just produced reads back as "already current".
  def expect_no_drift(record, category:)
    content = read_file(Pipeline::BibleEntryDocWriter::FILE_MAP.fetch(category))
    pending = Pipeline::BibleEntryMatcher.new(novel).classify(category, content)
    expect(pending).to be_empty
  end

  describe "#write" do
    context "characters" do
      subject(:writer) { described_class.new(@novel_dir, :characters) }

      it "creates the bible directory and writes the file" do
        character = create(:bible_character, novel: novel, name: "Hyuk Kang", korean_name: "강혁")
        writer.write([ character ])

        expect(File.directory?(File.join(@novel_dir, "bible"))).to be true
        expect(read_file("characters.md")).to include("## Hyuk Kang (강혁)")
      end

      it "writes fields the matcher reads back with no drift" do
        character = create(:bible_character,
          novel: novel, name: "Hyuk Kang", korean_name: "강혁",
          role: "Protagonist", aliases: "강실장", notes: "Founded K Management.",
          first_appearance_chapter: 1)
        writer.write([ character ])

        expect_no_drift(character, category: :characters)
      end

      it "omits blank fields rather than writing empty dash lines" do
        character = create(:bible_character, novel: novel, name: "Hyuk Kang", role: nil)
        writer.write([ character ])

        expect(read_file("characters.md")).not_to match(/- Role:\s*$/)
      end

      it "writes multiple records in the given order" do
        a = create(:bible_character, novel: novel, name: "Anya")
        b = create(:bible_character, novel: novel, name: "Zara")
        writer.write([ a, b ])

        content = read_file("characters.md")
        expect(content.index("Anya")).to be < content.index("Zara")
      end

      it "fully overwrites stale content from a previous write rather than appending" do
        old = create(:bible_character, novel: novel, name: "Old Name")
        writer.write([ old ])
        new_char = create(:bible_character, novel: novel, name: "New Name")
        writer.write([ new_char ])

        content = read_file("characters.md")
        expect(content).not_to include("Old Name")
        expect(content).to include("New Name")
      end

      it "removes an existing file when given no records" do
        character = create(:bible_character, novel: novel)
        writer.write([ character ])
        writer.write([])

        expect(File.exist?(file_path("characters.md"))).to be false
      end

      it "is a no-op when given no records and no file exists yet" do
        expect { writer.write([]) }.not_to raise_error
        expect(File.exist?(file_path("characters.md"))).to be false
      end

      it "does not raise when novel_dir is blank" do
        character = build(:bible_character, novel: novel)
        expect { described_class.new(nil, :characters).write([ character ]) }.not_to raise_error
        expect { described_class.new("", :characters).write([ character ]) }.not_to raise_error
      end
    end

    context "locations" do
      subject(:writer) { described_class.new(@novel_dir, :locations) }

      it "writes fields the matcher reads back with no drift" do
        location = create(:bible_location,
          novel: novel, name: "HS Entertainment", korean_name: "HS엔터테인먼트",
          significance: "Major agency.", first_appearance_chapter: 1)
        writer.write([ location ])

        expect_no_drift(location, category: :locations)
      end
    end

    context "terminology" do
      subject(:writer) { described_class.new(@novel_dir, :terminology) }

      it "writes fields the matcher reads back with no drift" do
        term = create(:bible_terminology,
          novel: novel, term: "Blue Sherbet", korean_term: "블루샤벳",
          definition: "Kang's former idol group.", usage_notes: "Proper noun.")
        writer.write([ term ])

        expect_no_drift(term, category: :terminology)
      end
    end

    context "cultural_phrases" do
      subject(:writer) { described_class.new(@novel_dir, :cultural_phrases) }

      it "writes a Korean-only heading, no English label" do
        phrase = create(:bible_cultural_phrase, novel: novel, korean_phrase: "떡줄 사람은 생각도 않는데")
        writer.write([ phrase ])

        expect(read_file("cultural_phrases.md")).to include("## 떡줄 사람은 생각도 않는데")
      end

      it "writes fields the matcher reads back with no drift" do
        phrase = create(:bible_cultural_phrase,
          novel: novel, korean_phrase: "떡줄 사람은 생각도 않는데",
          literal_translation: "The one giving rice cake isn't even thinking about it.",
          intended_meaning: "Premature assumption.", context: "Used sarcastically.")
        writer.write([ phrase ])

        expect_no_drift(phrase, category: :cultural_phrases)
      end
    end

    context "story" do
      subject(:writer) { described_class.new(@novel_dir, :story) }

      it "writes fields the matcher reads back with no drift" do
        entry = create(:bible_story_entry,
          novel: novel, title: "Main Plot", category: "main_plot",
          content: "Kang rebuilds his agency after regression.")
        writer.write([ entry ])

        expect_no_drift(entry, category: :story)
      end
    end
  end
end
