require "rails_helper"

RSpec.describe Pipeline::BibleEntrySuggestion do
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def config_for(claude_bin)
    TranslationConfig.from_env("PATH" => "", "CLAUDE_BIN" => claude_bin)
  end

  def scripted_claude(bin_dir, response)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      STDIN.read
      puts #{{ is_error: false, result: response.to_json }.to_json.inspect}
    RUBY
  end

  it "returns the Korean equivalent and the type's fields on success" do
    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, {
        korean_name: "최민재",
        role:        "Rival swordsman",
        aliases:     "",
        notes:       "Uses formal speech (-습니다) toward the protagonist."
      })

      result = described_class.call(
        entry_type:         "bible_character",
        english_text:       "Choi Min-jae",
        context_text:       "Choi Min-jae stepped into the courtyard, blade drawn.",
        korean_source_text: "최민재가 마당으로 들어서며 칼을 뽑았다.",
        config:             config_for(bin)
      )

      expect(result.ok?).to eq(true)
      expect(result.fields).to eq(
        "korean_name" => "최민재",
        "role"        => "Rival swordsman",
        "notes"       => "Uses formal speech (-습니다) toward the protagonist."
      )
    end
  end

  it "drops blank fields from the result rather than overwriting the form with emptiness" do
    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, { korean_term: "봉황의 불꽃", definition: "", usage_notes: "", notes: "" })

      result = described_class.call(
        entry_type:         "bible_terminology",
        english_text:       "Phoenix Flame",
        context_text:       "context",
        korean_source_text: "봉황의 불꽃",
        config:             config_for(bin)
      )

      expect(result.ok?).to eq(true)
      expect(result.fields).to eq("korean_term" => "봉황의 불꽃")
    end
  end

  it "ignores keys outside the type's field set, even if the model returns them" do
    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, {
        korean_name: "붉은 봉우리", significance: "A sacred site", notes: "",
        made_up_field: "should never appear", role: "should not appear for a location"
      })

      result = described_class.call(
        entry_type:         "bible_location",
        english_text:       "Crimson Peak",
        context_text:       "context",
        korean_source_text: "붉은 봉우리",
        config:             config_for(bin)
      )

      expect(result.ok?).to eq(true)
      expect(result.fields).to eq("korean_name" => "붉은 봉우리", "significance" => "A sacred site")
    end
  end

  it "degrades to an empty result without raising when the CLI call fails" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, "STDIN.read\nexit 1")

      result = described_class.call(
        entry_type:         "bible_character",
        english_text:       "Choi Min-jae",
        context_text:       "context",
        korean_source_text: "최민재",
        config:             config_for(bin)
      )

      expect(result.ok?).to eq(false)
      expect(result.fields).to eq({})
    end
  end

  it "degrades to an empty result without raising when the response isn't valid JSON" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        puts #{{ is_error: false, result: "not json" }.to_json.inspect}
      RUBY

      result = described_class.call(
        entry_type:         "bible_character",
        english_text:       "Choi Min-jae",
        context_text:       "context",
        korean_source_text: "최민재",
        config:             config_for(bin)
      )

      expect(result.ok?).to eq(false)
      expect(result.fields).to eq({})
    end
  end

  it "short-circuits without a call for an unknown entry_type" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, "raise 'should not be called'")

      result = described_class.call(
        entry_type:         "bible_story_entry",
        english_text:       "A Note",
        context_text:       "context",
        korean_source_text: "some korean text",
        config:             config_for(bin)
      )

      expect(result.ok?).to eq(true)
      expect(result.fields).to eq({})
    end
  end

  it "short-circuits without a call when there's no Korean source text" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, "raise 'should not be called'")

      result = described_class.call(
        entry_type:         "bible_character",
        english_text:       "Choi Min-jae",
        context_text:       "context",
        korean_source_text: nil,
        config:             config_for(bin)
      )

      expect(result.ok?).to eq(true)
      expect(result.fields).to eq({})
    end
  end
end
