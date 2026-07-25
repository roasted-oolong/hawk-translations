require "rails_helper"

# Deliberately uses arbitrary text fixtures, never bible markdown — proves the
# "no bible-domain knowledge" acceptance criterion directly (see
# docs/RAILS_REFACTOR_PLAN.md's R6 section).
RSpec.describe Pipeline::BibleFileEditor do
  subject(:editor) { described_class.new }

  describe "#append_block" do
    it "yields the freshly-read content and writes back whatever the block returns" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "notes.md")
        File.write(path, "existing\n")

        result = editor.append_block(path) { |fresh| fresh + "added\n" }

        expect(result).to eq(:applied)
        expect(File.read(path)).to eq("existing\nadded\n")
      end
    end

    it "yields an empty string for a file that doesn't exist yet, and creates it" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "nested", "notes.md")
        seen = nil

        editor.append_block(path) { |fresh| seen = fresh; "new content\n" }

        expect(seen).to eq("")
        expect(File.read(path)).to eq("new content\n")
      end
    end

    it "writes nothing when the block returns the SKIP sentinel" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "notes.md")
        File.write(path, "unchanged\n")

        result = editor.append_block(path) { Pipeline::BibleFileEditor::SKIP }

        expect(result).to eq(Pipeline::BibleFileEditor::SKIP)
        expect(File.read(path)).to eq("unchanged\n")
      end
    end

    it "leaves no .tmp file behind after a write" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "notes.md")
        editor.append_block(path) { "content\n" }

        expect(Dir.glob("#{dir}/*.tmp")).to be_empty
      end
    end

    it "serializes concurrent writers and gives the second writer the first writer's fresh output" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "notes.md")
        File.write(path, "start\n")
        first_started = Queue.new

        t1 = Thread.new do
          editor.append_block(path) do |fresh|
            first_started << true
            sleep 0.2
            fresh + "from-first\n"
          end
        end
        first_started.pop

        t2 = Thread.new do
          editor.append_block(path) { |fresh| fresh + "from-second\n" }
        end

        [ t1, t2 ].each(&:join)
        expect(File.read(path)).to eq("start\nfrom-first\nfrom-second\n")
      end
    end
  end

  describe "#replace" do
    it "applies the replacement when the target text occurs exactly once" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "notes.md")
        File.write(path, "before X after\n")

        result = editor.replace(path, current: "X", proposed: "Y")

        expect(result).to eq(:applied)
        expect(File.read(path)).to eq("before Y after\n")
      end
    end

    it "does not interpret backslash sequences in the proposed text" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "notes.md")
        File.write(path, "before X after\n")

        editor.replace(path, current: "X", proposed: 'literal \1 backslash')

        expect(File.read(path)).to eq('before literal \1 backslash after' + "\n")
      end
    end

    it "skips with :skipped_not_found when the target text is absent" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "notes.md")
        File.write(path, "no match here\n")

        result = editor.replace(path, current: "X", proposed: "Y")

        expect(result).to eq(:skipped_not_found)
        expect(File.read(path)).to eq("no match here\n")
      end
    end

    it "skips with :skipped_ambiguous when the target text occurs more than once" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "notes.md")
        File.write(path, "X and X again\n")

        result = editor.replace(path, current: "X", proposed: "Y")

        expect(result).to eq(:skipped_ambiguous)
        expect(File.read(path)).to eq("X and X again\n")
      end
    end
  end
end
