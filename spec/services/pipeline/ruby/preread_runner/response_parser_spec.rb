require "rails_helper"

RSpec.describe Pipeline::Ruby::PrereadRunner::ResponseParser do
  def raw_response(characters: "NOTHING TO ADD", locations: "NOTHING TO ADD",
                    terminology: "NOTHING TO ADD", cultural_phrases: "NOTHING TO ADD",
                    story: "NOTHING TO ADD")
    <<~RESPONSE
      === CHARACTERS ===
      #{characters}

      === LOCATIONS ===
      #{locations}

      === TERMINOLOGY ===
      #{terminology}

      === CULTURAL PHRASES ===
      #{cultural_phrases}

      === STORY ===
      #{story}
    RESPONSE
  end

  it "parses populated sections into their canonical keys" do
    result = described_class.parse(raw_response(characters: "## New Character\n- Role: rival"))

    expect(result.success?).to eq(true)
    expect(result.sections[:characters]).to eq("## New Character\n- Role: rival")
  end

  it "normalizes NOTHING TO ADD to an empty string" do
    result = described_class.parse(raw_response)

    expect(result.sections.values).to all(eq(""))
  end

  it "is case-insensitive and whitespace-tolerant when detecting NOTHING TO ADD" do
    result = described_class.parse(raw_response(story: "  nothing to add  "))

    expect(result.sections[:story]).to eq("")
  end

  it "returns empty content for a section whose header is present among others but this one omitted" do
    raw = "=== CHARACTERS ===\nsomething\n=== STORY ===\nan update"
    result = described_class.parse(raw)

    expect(result.success?).to eq(true)
    expect(result.sections[:characters]).to eq("something")
    expect(result.sections[:locations]).to eq("")
    expect(result.sections[:story]).to eq("an update")
  end

  it "fails closed when the response contains none of the five section markers at all" do
    result = described_class.parse("The model just wrote a paragraph with no structure.")

    expect(result.success?).to eq(false)
    expect(result.missing_markers).to eq(true)
  end
end
