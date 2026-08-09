require "rails_helper"

RSpec.describe Pipeline::Skills::BibleLookup do
  it "includes the shared Pipeline::Skill interface" do
    expect(described_class.ancestors).to include(Pipeline::Skill)
  end

  describe "#tool_definition / #name" do
    it "describes a provider-neutral bible_lookup tool schema" do
      skill = described_class.new(novel_directory_name: "some-novel")

      definition = skill.tool_definition
      expect(definition[:type]).to eq("function")
      expect(definition[:function][:name]).to eq("bible_lookup")
      expect(definition[:function][:parameters][:required]).to eq([ "query" ])
      expect(skill.name).to eq("bible_lookup")
    end
  end

  describe "#execute — argument handling (unit, BibleSearchService stubbed)" do
    let(:novel) { build_stubbed(:novel, directory_name: "idols-rewind") }
    let(:skill) { described_class.new(novel_directory_name: "idols-rewind") }

    before do
      allow(Novel).to receive(:find_by!).with(directory_name: "idols-rewind").and_return(novel)
    end

    it "returns an error string for a blank query, without touching search" do
      expect(BibleSearchService).not_to receive(:new)

      expect(skill.execute("query" => "  ")).to eq("[bible_lookup error: empty query]")
    end

    it "accepts string-keyed or symbol-keyed tool_args identically" do
      allow(BibleSearchService).to receive(:new).and_return(instance_double(BibleSearchService, call: []))

      expect(skill.execute({ "query" => "grumpy mentor" })).to eq(skill.execute({ query: "grumpy mentor" }))
    end

    it "passes categories through to BibleSearchService, limited to 5 results" do
      service = instance_double(BibleSearchService, call: [])
      expect(BibleSearchService).to receive(:new).with(
        scope: novel, query: "Kang", categories: [ "BibleCharacter" ], limit: 5
      ).and_return(service)

      skill.execute("query" => "Kang", "categories" => [ "BibleCharacter" ])
    end

    it "passes categories: nil when none are given" do
      service = instance_double(BibleSearchService, call: [])
      expect(BibleSearchService).to receive(:new).with(
        scope: novel, query: "Kang", categories: nil, limit: 5
      ).and_return(service)

      skill.execute("query" => "Kang")
    end

    it "returns a not-found message when the search yields nothing" do
      allow(BibleSearchService).to receive(:new).and_return(instance_double(BibleSearchService, call: []))

      expect(skill.execute("query" => "nobody")).to eq("No bible entries found for: nobody")
    end

    it "never raises when BibleSearchService itself errors" do
      allow(BibleSearchService).to receive(:new).and_raise(StandardError, "voyage down")

      expect { skill.execute("query" => "Kang") }.not_to raise_error
      expect(skill.execute("query" => "Kang")).to eq("[bible_lookup error: voyage down]")
    end
  end

  describe "#execute — novel resolution" do
    it "resolves Novel.find_by! once and memoizes it across calls on the same instance" do
      novel = build_stubbed(:novel, directory_name: "idols-rewind")
      expect(Novel).to receive(:find_by!).with(directory_name: "idols-rewind").once.and_return(novel)
      allow(BibleSearchService).to receive(:new).and_return(instance_double(BibleSearchService, call: []))

      skill = described_class.new(novel_directory_name: "idols-rewind")
      skill.execute("query" => "first")
      skill.execute("query" => "second")
    end

    it "rescues a missing novel into an error string instead of raising" do
      allow(Novel).to receive(:find_by!).and_raise(ActiveRecord::RecordNotFound, "not found")
      skill = described_class.new(novel_directory_name: "nope")

      expect(skill.execute("query" => "Kang")).to eq(
        "[bible_lookup error: could not resolve novel — not found]"
      )
    end

    it "never shares novel resolution across two separate instances" do
      novel_a = build_stubbed(:novel, directory_name: "novel-a")
      novel_b = build_stubbed(:novel, directory_name: "novel-b")
      allow(Novel).to receive(:find_by!).with(directory_name: "novel-a").and_return(novel_a)
      allow(Novel).to receive(:find_by!).with(directory_name: "novel-b").and_return(novel_b)

      scopes_seen = []
      allow(BibleSearchService).to receive(:new) do |scope:, **|
        scopes_seen << scope
        instance_double(BibleSearchService, call: [])
      end

      described_class.new(novel_directory_name: "novel-a").execute("query" => "x")
      described_class.new(novel_directory_name: "novel-b").execute("query" => "x")

      expect(scopes_seen).to eq([ novel_a, novel_b ])
    end
  end

  describe "#execute — formatting (unit, real records, BibleSearchService stubbed)" do
    let(:novel) { build_stubbed(:novel, directory_name: "idols-rewind") }
    let(:skill) { described_class.new(novel_directory_name: "idols-rewind") }

    before do
      allow(Novel).to receive(:find_by!).and_return(novel)
    end

    def stub_results(results)
      allow(BibleSearchService).to receive(:new).and_return(instance_double(BibleSearchService, call: results))
    end

    it "formats a BibleCharacter result with a [Character] header, skipping blank fields" do
      character = build_stubbed(:bible_character, novel: novel, name: "Hyuk Kang", korean_name: "강혁",
                                 role: "Protagonist", notes: nil)
      stub_results([ { embeddable_type: "BibleCharacter", record: character } ])

      output = skill.execute("query" => "Hyuk")

      expect(output).to eq(
        "[Character]\nName: Hyuk Kang\nKorean name: 강혁\nRole: Protagonist"
      )
    end

    it "formats a BibleLocation result with a [Location] header" do
      location = build_stubbed(:bible_location, novel: novel, name: "HS Entertainment", location_type: "Office")
      stub_results([ { embeddable_type: "BibleLocation", record: location } ])

      expect(skill.execute("query" => "HS")).to eq(
        "[Location]\nName: HS Entertainment\nType: Office"
      )
    end

    it "formats a BibleTerminology result with a [Terminology] header" do
      term = build_stubbed(:bible_terminology, novel: novel, term: "sunbae", definition: "senior peer")
      stub_results([ { embeddable_type: "BibleTerminology", record: term } ])

      expect(skill.execute("query" => "sunbae")).to eq(
        "[Terminology]\nTerm: sunbae\nDefinition: senior peer"
      )
    end

    it "formats a BibleCulturalPhrase result with a [Cultural Phrase] header" do
      phrase = build_stubbed(:bible_cultural_phrase, novel: novel, korean_phrase: "아이고", literal_translation: "oh dear")
      stub_results([ { embeddable_type: "BibleCulturalPhrase", record: phrase } ])

      expect(skill.execute("query" => "아이고")).to eq(
        "[Cultural Phrase]\nKorean phrase: 아이고\nLiteral translation: oh dear"
      )
    end

    it "includes translation_examples_text for a BibleCulturalPhrase result that has logged examples" do
      phrase = build_stubbed(:bible_cultural_phrase, novel: novel, korean_phrase: "아이고")
      phrase.translation_examples_text = "sighing: oh dear\nexasperated: for goodness' sake"
      stub_results([ { embeddable_type: "BibleCulturalPhrase", record: phrase } ])

      result = skill.execute("query" => "아이고")
      expect(result).to include("Translation examples: sighing: oh dear\nexasperated: for goodness' sake")
    end

    it "formats a BibleStoryEntry result with a [Story Entry] header" do
      entry = build_stubbed(:bible_story_entry, novel: novel, title: "The Debut", category: "main_plot")
      stub_results([ { embeddable_type: "BibleStoryEntry", record: entry } ])

      expect(skill.execute("query" => "debut")).to eq(
        "[Story Entry]\nTitle: The Debut\nCategory: main_plot"
      )
    end

    it "joins multiple results with a blank line between them" do
      character = build_stubbed(:bible_character, novel: novel, name: "Hyuk Kang")
      location  = build_stubbed(:bible_location, novel: novel, name: "HS Entertainment")
      stub_results([
        { embeddable_type: "BibleCharacter", record: character },
        { embeddable_type: "BibleLocation", record: location }
      ])

      expect(skill.execute("query" => "x")).to eq(
        "[Character]\nName: Hyuk Kang\n\n[Location]\nName: HS Entertainment"
      )
    end
  end
end
