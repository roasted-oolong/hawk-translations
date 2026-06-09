require "rails_helper"

RSpec.describe BibleMarkdownParser do
  let(:novel) { create(:novel) }

  describe "#pending_entries" do
    context "when the bible directory does not exist" do
      before { allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return("") }

      it "returns empty collections for all categories" do
        result = described_class.new(novel).pending_entries
        expect(result.values.all?(&:empty?)).to be true
      end
    end

    context "with dismissed keys stored on the novel" do
      let(:bible_dir) { Dir.mktmpdir }

      before do
        FileUtils.mkdir_p(File.join(bible_dir, "bible"))
        allow(ENV).to receive(:fetch).with("HAWK_PROJECT_ROOT", "").and_return(File.dirname(bible_dir))
        allow(novel).to receive(:directory_name).and_return(File.basename(bible_dir))

        File.write(File.join(bible_dir, "bible", "characters.md"), <<~MD)
          ## Park Jisoo (박지수)
          - Korean name: 박지수
          - Role: Protagonist

          ## Kim Minjun (김민준)
          - Korean name: 김민준
          - Role: Antagonist
        MD

        %w[locations.md terminology.md cultural_phrases.md story.md].each do |f|
          FileUtils.touch(File.join(bible_dir, "bible", f))
        end
      end

      after { FileUtils.rm_rf(bible_dir) }

      it "includes all characters when none are dismissed" do
        result = described_class.new(novel).pending_entries
        names = result[:characters].map { |e| e[:name] }
        expect(names).to include("Park Jisoo", "Kim Minjun")
      end

      it "excludes characters whose composite key is in preread_dismissed_keys" do
        novel.update_column(:preread_dismissed_keys, '["characters:김민준"]')
        result = described_class.new(novel).pending_entries
        names = result[:characters].map { |e| e[:name] }
        expect(names).to include("Park Jisoo")
        expect(names).not_to include("Kim Minjun")
      end
    end
  end
end
