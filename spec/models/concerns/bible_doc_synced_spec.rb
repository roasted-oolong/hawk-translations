# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# BibleDocSynced concern spec
#
# Tests the contract the concern establishes:
# - Including classes must implement #bible_doc_category
# - #bible_doc_category raises NotImplementedError if not overridden
# - The after_commit hook regenerates that novel's bible/*.md file on
#   create, update, AND destroy
#
# Mirrors spec/models/concerns/embeddable_spec.rb's shape. Each concrete
# model's own spec (once added) can assert its file's exact field content;
# this spec tests only the shared contract, via bible_character as the one
# representative real model.
# =============================================================================
RSpec.describe BibleDocSynced, type: :model do
  let(:bare_class) do
    Class.new do
      def self.after_commit(*); end

      include BibleDocSynced
    end
  end

  describe "#bible_doc_category" do
    it "raises NotImplementedError on a class that does not implement it" do
      instance = bare_class.new
      expect { instance.bible_doc_category }.to raise_error(NotImplementedError, /bible_doc_category/)
    end
  end

  describe "after_commit hook via a real model" do
    around do |example|
      Dir.mktmpdir do |dir|
        @novel_dir = dir
        example.run
      end
    end

    let(:novel) { create(:novel, directory_name: File.basename(@novel_dir)) }

    before do
      @orig_root = ENV["HAWK_PROJECT_ROOT"]
      ENV["HAWK_PROJECT_ROOT"] = File.dirname(@novel_dir)
    end

    after { ENV["HAWK_PROJECT_ROOT"] = @orig_root }

    def characters_md
      File.join(@novel_dir, "bible", "characters.md")
    end

    it "writes bible/characters.md on create" do
      create(:bible_character, novel: novel, name: "Hyuk Kang")

      expect(File.exist?(characters_md)).to be true
      expect(File.read(characters_md)).to include("Hyuk Kang")
    end

    it "rewrites bible/characters.md on update" do
      character = create(:bible_character, novel: novel, name: "Old Name")
      character.update!(name: "New Name")

      content = File.read(characters_md)
      expect(content).to include("New Name")
      expect(content).not_to include("Old Name")
    end

    it "removes the entry from bible/characters.md on destroy" do
      character = create(:bible_character, novel: novel, name: "Hyuk Kang")
      other     = create(:bible_character, novel: novel, name: "Hee-yeon Lee")
      character.destroy!

      content = File.read(characters_md)
      expect(content).not_to include("Hyuk Kang")
      expect(content).to include("Hee-yeon Lee")
    end

    it "does not raise when the file write fails (e.g. HAWK_PROJECT_ROOT unset)" do
      ENV["HAWK_PROJECT_ROOT"] = ""
      expect { create(:bible_character, novel: novel, name: "Hyuk Kang") }.not_to raise_error
    end
  end
end
