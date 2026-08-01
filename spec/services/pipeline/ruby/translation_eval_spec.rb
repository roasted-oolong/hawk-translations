require "rails_helper"
require "json"

# Offline-only tool (docs/ROADMAP.md's translation quality pipeline note):
# runs the 5-step pipeline (docs/DECISIONS.md's 2026-08-01 "5-step pipeline
# replaces 3-call pipeline" entry, updated by the hybrid beat segmentation
# entry) over the given chapters, so a human can judge quality/cost/
# JSON-reliability before any pipeline goes into production. Not wired into
# translate_batch or any TranslationJob — takes a plain directory, not a
# Novel record. The single-pass and structured (intent/literal/localized)
# prompts were dropped from this harness entirely — they're not part of the
# pipeline under test, so running them alongside it only burned extra calls.
RSpec.describe Pipeline::Ruby::TranslationEval do
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def config_for(claude_bin)
    TranslationConfig.from_env("PATH" => "", "CLAUDE_BIN" => claude_bin)
  end

  def build_novel_dir(root)
    dir = File.join(root, "test-novel")
    FileUtils.mkdir_p(File.join(dir, "bible"))
    FileUtils.mkdir_p(File.join(dir, "chapters"))
    dir
  end

  def write_korean_source(novel_dir, num, text)
    File.write(File.join(novel_dir, "chapters", "Chapter #{num} (Korean).txt"), text)
  end

  # Step 1 is now a deterministic/semantic hybrid (see BeatSegmenter and
  # PromptBuilder.build_beat_classification_system_prompt): a single Korean
  # sentence with no blank-line break is always exactly one candidate block
  # (and therefore one final passage). Tests that need more than one passage
  # use this instead — 10 short blank-line-separated paragraphs always chunk
  # into exactly two candidate blocks (7 + 3, verified against
  # BeatSegmenter.candidate_blocks directly), giving predictable multi-passage
  # fixtures without hand-crafting anchor_quote text the LLM no longer supplies.
  def two_passage_korean_text
    (1..10).map { |i| "문단 #{i} 내용입니다." }.join("\n\n")
  end

  def candidate_blocks_for(korean_text)
    Pipeline::Ruby::TranslateBatch::BeatSegmenter.candidate_blocks(korean_text)
  end

  # Every candidate block labeled BREAK relative to the one before it, so
  # merge_beats produces exactly one final passage per candidate block (the
  # simplest, most predictable mapping) unless a test overrides individual
  # labels to exercise CONTINUE/BRIDGE merging directly.
  def all_break_classification(korean_text, speaker: "narration")
    blocks = candidate_blocks_for(korean_text).reject(&:scene_break)
    { blocks: blocks.map { |b| { block_id: b.block_id, speaker: speaker, label: "BREAK" } } }
  end

  def passage_ids_for(korean_text)
    candidate_blocks_for(korean_text).reject(&:scene_break).map.with_index { |_, i| { passage_id: i + 1 } }
  end

  # All five calls for one chapter share the same fake claude binary, so
  # responses are keyed on [marker, variant]. `variant` is read back off the
  # --system-prompt-file content itself, since each call's system prompt has a
  # unique JSON-shape marker: beat classification (Step 1) is the only one
  # with "blocks", analysis the only one with "core_message", localization the
  # only one with "localized_passages", factcheck the only one with
  # "names_preserved", editor the only one with "continuous_utterance".
  #
  # `marker` disambiguates between chapters within the *stdin* (user message)
  # content. Every step except editor gets the Korean text somewhere in its
  # stdin (Step 1 directly, via the candidate blocks' verbatim text; analysis/
  # localization/factcheck via segmentation's anchor_quote flowing through) —
  # but editor is deliberately blind to the Korean, so its stdin only contains
  # English localized_translation text. An empty-string marker always matches
  # (used for every single-chapter test); multi-chapter tests pass a real
  # marker for the four Korean-visible steps and a separate marker (a substring
  # of that chapter's English text) for editor specifically.
  def scripted_claude(bin_dir, responses_by_marker_and_variant)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      stdin = STDIN.read.force_encoding("UTF-8")
      prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
      prompt = File.read(prompt_path)
      variant =
        if prompt.include?('"blocks"')
          "segmentation"
        elsif prompt.include?('"core_message"')
          "analysis"
        elsif prompt.include?('"localized_passages"')
          "localization"
        elsif prompt.include?('"names_preserved"')
          "factcheck"
        elsif prompt.include?('"continuous_utterance"')
          "editor"
        else
          raise "unrecognized system prompt variant"
        end
      responses = #{responses_by_marker_and_variant.inspect}
      match = responses.find { |(marker, v), _| stdin.include?(marker) && v == variant }
      raise "no scripted response for \#{variant}: \#{stdin[0,40].inspect}" unless match
      puts match[1].to_json
    RUBY
  end

  def default_analysis_payload(passages)
    {
      passages: passages.map do |p|
        { passage_id: p[:passage_id], core_message: "msg", emphasis: "e", pacing_rhythm: "p",
          voice_register: "v", narrative_function: "f", cultural_signals: "",
          localization_strategy: { category: "none", notes: "" }, bible_entries_used: [] }
      end
    }
  end

  def default_localization_payload(passages, english_marker: "x")
    { localized_passages: passages.map { |p| { passage_id: p[:passage_id], localized_translation: "#{english_marker}#{p[:passage_id]}" } } }
  end

  def default_factcheck_payload(passages)
    {
      reviewed_passages: passages.map do |p|
        { passage_id: p[:passage_id],
          checks: { names_preserved: true, facts_preserved: true, cultural_significance_preserved: true, cultural_dynamic_enacted: true },
          findings: [] }
      end,
      review_summary: { summary: "" }
    }
  end

  def default_editor_payload(passages)
    {
      reviewed_passages: passages.map do |p|
        { passage_id: p[:passage_id],
          checks: { continuous_utterance: true, register_unified: true, narrative_flow: true, natural_english: true },
          findings: [] }
      end,
      review_summary: { summary: "" }
    }
  end

  # Builds a full happy-path response table for one chapter, deriving Step 1's
  # classification response (all blocks labeled BREAK, one passage per
  # candidate block, unless overridden) and filling in default all-green
  # analysis/localization/factcheck/editor payloads unless overridden.
  # `marker` disambiguates the four Korean-visible steps; `editor_marker`
  # (default "" — always matches) disambiguates editor, which never sees the
  # Korean.
  def pipeline_responses(korean_text:, marker: "", editor_marker: "",
                          classification_payload: nil,
                          analysis_payload: nil, localization_payload: nil,
                          factcheck_payload: nil, editor_payload: nil)
    classification_payload ||= all_break_classification(korean_text)
    passages = passage_ids_for(korean_text)
    analysis_payload     ||= default_analysis_payload(passages)
    localization_payload ||= default_localization_payload(passages)
    factcheck_payload    ||= default_factcheck_payload(passages)
    editor_payload        ||= default_editor_payload(passages)

    {
      [ marker, "segmentation" ] => { is_error: false, result: classification_payload.to_json },
      [ marker, "analysis" ]     => { is_error: false, result: analysis_payload.to_json },
      [ marker, "localization" ] => { is_error: false, result: localization_payload.to_json },
      [ marker, "factcheck" ]    => { is_error: false, result: factcheck_payload.to_json },
      [ editor_marker, "editor" ] => { is_error: false, result: editor_payload.to_json }
    }
  end

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      Dir.mktmpdir do |out|
        @output_dir = out
        example.run
      end
    end
  end

  it "runs all 5 pipeline steps for a clean chapter" do
    novel_dir = build_novel_dir(@root)
    korean_text = "챕터 1 한국어"
    write_korean_source(novel_dir, 1, korean_text)

    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text))

      results = described_class.call(
        novel_dir: novel_dir, chapter_numbers: [ 1 ],
        output_dir: @output_dir, config: config_for(bin)
      )

      r = results.first
      expect(results.size).to eq(1)
      expect(r.number).to eq(1)
      expect(r.missing_source).to eq(false)
      expect(r.segmentation_error).to be_nil
      expect(r.segmentation_valid_json).to eq(true)
      expect(r.segmentation_coverage_error).to be_nil
      expect(r.analysis_error).to be_nil
      expect(r.analysis_valid_json).to eq(true)
      expect(r.analysis_coverage_error).to be_nil
      expect(r.localization_error).to be_nil
      expect(r.localization_valid_json).to eq(true)
      expect(r.localization_coverage_error).to be_nil
      expect(r.factcheck_error).to be_nil
      expect(r.factcheck_valid_json).to eq(true)
      expect(r.factcheck_coverage_error).to be_nil
      expect(r.factcheck_flagged_count).to eq(0)
      expect(r.editor_error).to be_nil
      expect(r.editor_valid_json).to eq(true)
      expect(r.editor_coverage_error).to be_nil
      expect(r.editor_flagged_count).to eq(0)

      chapter_dir = File.join(@output_dir, "chapter_1")
      expect(JSON.parse(File.read(File.join(chapter_dir, "classification.json")))["blocks"].first["block_id"]).to eq(1)
      segmentation = JSON.parse(File.read(File.join(chapter_dir, "segmentation.json")))
      expect(segmentation["passages"].first["passage_id"]).to eq(1)
      expect(segmentation["passages"].first["speakers"]).to eq([ "narration" ])
      expect(JSON.parse(File.read(File.join(chapter_dir, "analysis.json")))["passages"].first["core_message"]).to eq("msg")
      expect(JSON.parse(File.read(File.join(chapter_dir, "localization.json")))["localized_passages"].first["passage_id"]).to eq(1)
      expect(File.read(File.join(chapter_dir, "localized_chapter.txt"))).to eq("x1")
      expect(JSON.parse(File.read(File.join(chapter_dir, "factcheck.json")))["reviewed_passages"].first["passage_id"]).to eq(1)
      expect(JSON.parse(File.read(File.join(chapter_dir, "editor.json")))["reviewed_passages"].first["passage_id"]).to eq(1)
    end
  end

  it "passes bible/cultural_patterns.md content into analysis/localization/factcheck, not segmentation or editor" do
    novel_dir = build_novel_dir(@root)
    write_korean_source(novel_dir, 1, "챕터 1 한국어")
    File.write(File.join(novel_dir, "bible", "cultural_patterns.md"), "Status-jockeying pattern notes")

    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
        prompt = File.read(prompt_path)
        variant =
          if prompt.include?('"blocks"')
            "segmentation"
          elsif prompt.include?('"core_message"')
            "analysis"
          elsif prompt.include?('"localized_passages"')
            "localization"
          elsif prompt.include?('"names_preserved"')
            "factcheck"
          elsif prompt.include?('"continuous_utterance"')
            "editor"
          else
            raise "unrecognized system prompt variant"
          end

        leaked = prompt.include?("Status-jockeying pattern notes")
        case variant
        when "editor"
          raise "cultural_patterns content leaked into \#{variant} prompt" if leaked
          puts({ is_error: false, result: { reviewed_passages: [], review_summary: {} }.to_json }.to_json)
        when "segmentation"
          raise "cultural_patterns content leaked into segmentation prompt" if leaked
          puts({ is_error: false, result: { blocks: [ { block_id: 1, speaker: "narration", label: "BREAK" } ] }.to_json }.to_json)
        else
          raise "missing cultural_patterns content in \#{variant} prompt" unless leaked
          payload =
            case variant
            when "analysis" then { passages: [ { passage_id: 1, core_message: "m", emphasis: "e", pacing_rhythm: "p", voice_register: "v", narrative_function: "f", cultural_signals: "", localization_strategy: { category: "none", notes: "" }, bible_entries_used: [] } ] }
            when "localization" then { localized_passages: [ { passage_id: 1, localized_translation: "x" } ] }
            when "factcheck" then { reviewed_passages: [ { passage_id: 1, checks: {}, findings: [] } ], review_summary: {} }
            end
          puts({ is_error: false, result: payload.to_json }.to_json)
        end
      RUBY

      results = described_class.call(
        novel_dir: novel_dir, chapter_numbers: [ 1 ],
        output_dir: @output_dir, config: config_for(bin)
      )

      expect(results.first.segmentation_error).to be_nil
      expect(results.first.analysis_error).to be_nil
    end
  end

  it "skips chapters with no Korean source without calling claude" do
    novel_dir = build_novel_dir(@root)

    results = described_class.call(
      novel_dir: novel_dir, chapter_numbers: [ 1 ],
      output_dir: @output_dir, config: config_for("/bin/true")
    )

    expect(results.first.missing_source).to eq(true)
    expect(File.exist?(File.join(@output_dir, "chapter_1"))).to eq(false)
  end

  it "continues past a per-call failure on one chapter and still runs the rest" do
    novel_dir = build_novel_dir(@root)
    korean1 = "챕터 1 한국어"
    korean2 = "챕터 2 한국어"
    write_korean_source(novel_dir, 1, korean1)
    write_korean_source(novel_dir, 2, korean2)

    Dir.mktmpdir do |bin_dir|
      responses = {}
      responses.merge!(pipeline_responses(
        korean_text: korean1, marker: "챕터 1", editor_marker: "one",
        localization_payload: default_localization_payload(passage_ids_for(korean1), english_marker: "one")
      ))
      responses[[ "챕터 1", "segmentation" ]] = { is_error: true, subtype: "boom", result: "failed" }
      responses.merge!(pipeline_responses(
        korean_text: korean2, marker: "챕터 2", editor_marker: "two",
        localization_payload: default_localization_payload(passage_ids_for(korean2), english_marker: "two")
      ))

      bin = scripted_claude(bin_dir, responses)

      results = described_class.call(
        novel_dir: novel_dir, chapter_numbers: [ 1, 2 ],
        output_dir: @output_dir, config: config_for(bin)
      )

      chapter1, chapter2 = results

      expect(chapter1.segmentation_error).to include("cli_failure")
      expect(chapter1.analysis_error).to eq("skipped: segmentation did not produce valid, fully-covered passages")
      expect(File.exist?(File.join(@output_dir, "chapter_1", "segmentation.json"))).to eq(false)

      expect(chapter2.segmentation_error).to be_nil
      expect(chapter2.localization_error).to be_nil
      expect(File.read(File.join(@output_dir, "chapter_2", "localized_chapter.txt"))).to eq("two1")
    end
  end

  describe "Step 1 (beat classification / segmentation) validation" do
    it "passes when the classification response covers every candidate block, producing sequential passage_ids" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.segmentation_valid_json).to eq(true)
        expect(r.segmentation_coverage_error).to be_nil
        expect(r.analysis_error).to be_nil
        expect(r.analysis_coverage_error).to be_nil

        passages = JSON.parse(File.read(File.join(@output_dir, "chapter_1", "segmentation.json")))["passages"]
        expect(passages.map { |p| p["passage_id"] }).to eq([ 1, 2 ])
      end
    end

    it "reconstructs the source chapter's anchor_quote even when the source has irregular blank lines" do
      novel_dir = build_novel_dir(@root)
      korean_text = "챕터 1\n\n\n\n  \n\n한국어"
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.segmentation_coverage_error).to be_nil
      end
    end

    it "flags a coverage mismatch when the classification response omits a candidate block" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        incomplete = all_break_classification(korean_text)
        incomplete[:blocks] = incomplete[:blocks].first(1) # drop block 2
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text, classification_payload: incomplete))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.segmentation_valid_json).to eq(true)
        expect(r.segmentation_coverage_error).to include("missing")
        expect(r.analysis_error).to eq("skipped: segmentation did not produce valid, fully-covered passages")
      end
    end

    it "flags a coverage error when the classification response lists blocks out of order" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        reordered = all_break_classification(korean_text)
        reordered[:blocks] = reordered[:blocks].reverse
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text, classification_payload: reordered))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.segmentation_coverage_error).to include("does not match expected")
      end
    end

    it "flags a missing or empty blocks array in the classification response" do
      novel_dir = build_novel_dir(@root)
      korean_text = "챕터 1 한국어"
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text, classification_payload: { blocks: [] }))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.segmentation_coverage_error).to include("blocks")
      end
    end

    it "saves invalid classification JSON raw instead of crashing the run, and skips every later step" do
      novel_dir = build_novel_dir(@root)
      write_korean_source(novel_dir, 1, "챕터 1 한국어")

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir, {
          [ "", "segmentation" ] => { is_error: false, result: "not json at all" }
        })

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.segmentation_valid_json).to eq(false)
        expect(r.segmentation_error).to include("invalid JSON")
        expect(r.segmentation_coverage_error).to be_nil

        chapter_dir = File.join(@output_dir, "chapter_1")
        expect(File.read(File.join(chapter_dir, "segmentation.raw.txt"))).to eq("not json at all")
        expect(File.exist?(File.join(chapter_dir, "segmentation.json"))).to eq(false)

        expect(r.analysis_error).to eq("skipped: segmentation did not produce valid, fully-covered passages")
        expect(r.localization_error).to eq("skipped: analysis did not produce valid, fully-covered output")
        expect(r.factcheck_error).to eq("skipped: localization did not produce valid, fully-covered translation")
        expect(r.editor_error).to eq("skipped: localization did not produce valid, fully-covered translation")
      end
    end

    it "merges CONTINUE-labeled blocks into fewer final passages than raw candidate blocks, and still chains into analysis" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        block_ids = candidate_blocks_for(korean_text).reject(&:scene_break).map(&:block_id)
        expect(block_ids.size).to eq(2) # sanity: two raw candidate blocks going in

        merged_classification = {
          blocks: [
            { block_id: block_ids[0], speaker: "narration", label: "BREAK" },
            { block_id: block_ids[1], speaker: "narration", label: "CONTINUE" } # merges into one beat
          ]
        }
        # The merge collapses 2 candidate blocks into 1 final passage, so the
        # analysis response must match that merged shape, not the raw block count.
        bin = scripted_claude(bin_dir, pipeline_responses(
          korean_text: korean_text, classification_payload: merged_classification,
          analysis_payload: default_analysis_payload([ { passage_id: 1 } ])
        ))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.segmentation_coverage_error).to be_nil
        segmentation = JSON.parse(File.read(File.join(@output_dir, "chapter_1", "segmentation.json")))
        expect(segmentation["passages"].size).to eq(1) # 2 candidate blocks merged into 1 beat
        expect(r.analysis_error).to be_nil
        expect(r.analysis_coverage_error).to be_nil
      end
    end
  end

  describe "Step 2 (analysis) chaining and coverage validation" do
    it "flags a coverage mismatch when analysis drops a passage_id from segmentation" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        analysis_payload = default_analysis_payload([ { passage_id: 1 } ])
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text, analysis_payload: analysis_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.analysis_valid_json).to eq(true)
        expect(r.analysis_coverage_error).to include("missing passage_id(s) [2]")
        expect(r.localization_error).to eq("skipped: analysis did not produce valid, fully-covered output")
      end
    end

    it "saves invalid analysis JSON raw instead of crashing the run, and skips localization/factcheck/editor" do
      novel_dir = build_novel_dir(@root)
      korean_text = "챕터 1 한국어"
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        responses = pipeline_responses(korean_text: korean_text)
          .merge([ "", "analysis" ] => { is_error: false, result: "not json at all" })
        bin = scripted_claude(bin_dir, responses)

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.analysis_valid_json).to eq(false)
        expect(r.analysis_error).to include("invalid JSON")

        chapter_dir = File.join(@output_dir, "chapter_1")
        expect(File.read(File.join(chapter_dir, "analysis.raw.txt"))).to eq("not json at all")
        expect(File.exist?(File.join(chapter_dir, "analysis.json"))).to eq(false)

        expect(r.localization_error).to eq("skipped: analysis did not produce valid, fully-covered output")
        expect(r.factcheck_error).to eq("skipped: localization did not produce valid, fully-covered translation")
        expect(r.editor_error).to eq("skipped: localization did not produce valid, fully-covered translation")
      end
    end
  end

  describe "Step 3 (localization) chaining and coverage validation" do
    it "flags a coverage mismatch when localized_passages drops a passage_id from analysis" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        localization_payload = { localized_passages: [ { passage_id: 1, localized_translation: "one" } ] }
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text, localization_payload: localization_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.localization_valid_json).to eq(true)
        expect(r.localization_coverage_error).to include("missing passage_id(s) [2]")
        expect(File.exist?(File.join(@output_dir, "chapter_1", "localized_chapter.txt"))).to eq(false)
        expect(r.factcheck_error).to eq("skipped: localization did not produce valid, fully-covered translation")
        expect(r.editor_error).to eq("skipped: localization did not produce valid, fully-covered translation")
      end
    end

    it "reassembles localized_translation into a full chapter in passage_id order when coverage matches" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        localization_payload = {
          localized_passages: [
            { passage_id: 1, localized_translation: "Chapter one, " },
            { passage_id: 2, localized_translation: "Korean." }
          ]
        }
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text, localization_payload: localization_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.localization_coverage_error).to be_nil
        expect(File.read(File.join(@output_dir, "chapter_1", "localized_chapter.txt"))).to eq("Chapter one, Korean.")
        expect(r.factcheck_coverage_error).to be_nil
        expect(r.editor_coverage_error).to be_nil
      end
    end

    it "saves invalid localization JSON raw instead of crashing the run, and skips factcheck/editor" do
      novel_dir = build_novel_dir(@root)
      korean_text = "챕터 1 한국어"
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        responses = pipeline_responses(korean_text: korean_text)
          .merge([ "", "localization" ] => { is_error: false, result: "not json at all" })
        bin = scripted_claude(bin_dir, responses)

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.localization_valid_json).to eq(false)
        expect(r.localization_error).to include("invalid JSON")

        chapter_dir = File.join(@output_dir, "chapter_1")
        expect(File.read(File.join(chapter_dir, "localization.raw.txt"))).to eq("not json at all")
        expect(File.exist?(File.join(chapter_dir, "localization.json"))).to eq(false)

        expect(r.factcheck_error).to eq("skipped: localization did not produce valid, fully-covered translation")
        expect(r.editor_error).to eq("skipped: localization did not produce valid, fully-covered translation")
      end
    end
  end

  describe "Steps 4/5 (factcheck, editor) independent review chaining and coverage validation" do
    it "flags a coverage mismatch when factcheck's reviewed_passages drops a passage_id from localization" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        factcheck_payload = { reviewed_passages: [ { passage_id: 1, checks: {}, findings: [] } ], review_summary: {} }
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text, factcheck_payload: factcheck_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.factcheck_valid_json).to eq(true)
        expect(r.factcheck_coverage_error).to include("missing passage_id(s) [2]")
        # Editor is independent of factcheck — its own coverage is untouched.
        expect(r.editor_coverage_error).to be_nil
      end
    end

    it "flags a coverage mismatch when editor's reviewed_passages drops a passage_id from localization" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        editor_payload = { reviewed_passages: [ { passage_id: 1, checks: {}, findings: [] } ], review_summary: {} }
        bin = scripted_claude(bin_dir, pipeline_responses(korean_text: korean_text, editor_payload: editor_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.editor_valid_json).to eq(true)
        expect(r.editor_coverage_error).to include("missing passage_id(s) [2]")
        # Factcheck is independent of editor — its own coverage is untouched.
        expect(r.factcheck_coverage_error).to be_nil
      end
    end

    it "counts a passage as flagged when any check is false or it has findings, for factcheck and editor independently" do
      novel_dir = build_novel_dir(@root)
      korean_text = two_passage_korean_text
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        factcheck_payload = {
          reviewed_passages: [
            { passage_id: 1, checks: { names_preserved: true, facts_preserved: false }, findings: [ { quote: "x", issue: "dropped a name" } ] },
            { passage_id: 2, checks: { names_preserved: true, facts_preserved: true }, findings: [] }
          ],
          review_summary: { summary: "One passage needs work." }
        }
        editor_payload = {
          reviewed_passages: [
            { passage_id: 1, checks: { continuous_utterance: true, natural_english: true }, findings: [] },
            { passage_id: 2, checks: { continuous_utterance: false, natural_english: true }, findings: [ { quote: "y", issue: "choppy" } ] }
          ],
          review_summary: { summary: "One passage needs work." }
        }
        bin = scripted_claude(bin_dir, pipeline_responses(
          korean_text: korean_text, factcheck_payload: factcheck_payload, editor_payload: editor_payload
        ))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.factcheck_coverage_error).to be_nil
        expect(r.factcheck_flagged_count).to eq(1)
        expect(r.editor_coverage_error).to be_nil
        expect(r.editor_flagged_count).to eq(1)
      end
    end

    it "saves invalid factcheck JSON raw instead of crashing the run, without affecting editor" do
      novel_dir = build_novel_dir(@root)
      korean_text = "챕터 1 한국어"
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        responses = pipeline_responses(korean_text: korean_text)
          .merge([ "", "factcheck" ] => { is_error: false, result: "not json at all" })
        bin = scripted_claude(bin_dir, responses)

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.factcheck_valid_json).to eq(false)
        expect(r.factcheck_error).to include("invalid JSON")

        chapter_dir = File.join(@output_dir, "chapter_1")
        expect(File.read(File.join(chapter_dir, "factcheck.raw.txt"))).to eq("not json at all")
        expect(File.exist?(File.join(chapter_dir, "factcheck.json"))).to eq(false)

        expect(r.editor_error).to be_nil
        expect(r.editor_valid_json).to eq(true)
      end
    end

    it "calls factcheck with factcheck_model instead of translation_model, leaving every other step on translation_model" do
      novel_dir = build_novel_dir(@root)
      korean_text = "챕터 1 한국어"
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        models_log = File.join(bin_dir, "models.log")
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
          prompt = File.read(prompt_path)
          model = ARGV[ARGV.index("--model") + 1]
          variant =
            if prompt.include?('"blocks"')
              "segmentation"
            elsif prompt.include?('"core_message"')
              "analysis"
            elsif prompt.include?('"localized_passages"')
              "localization"
            elsif prompt.include?('"names_preserved"')
              "factcheck"
            elsif prompt.include?('"continuous_utterance"')
              "editor"
            end
          File.open(#{models_log.inspect}, "a") { |f| f.puts "\#{variant}:\#{model}" }

          payload =
            case variant
            when "segmentation" then { blocks: [ { block_id: 1, speaker: "narration", label: "BREAK" } ] }
            when "analysis" then { passages: [ { passage_id: 1, core_message: "m", emphasis: "e", pacing_rhythm: "p", voice_register: "v", narrative_function: "f", cultural_signals: "", localization_strategy: { category: "none", notes: "" }, bible_entries_used: [] } ] }
            when "localization" then { localized_passages: [ { passage_id: 1, localized_translation: "x" } ] }
            when "factcheck" then { reviewed_passages: [ { passage_id: 1, checks: {}, findings: [] } ], review_summary: {} }
            when "editor" then { reviewed_passages: [ { passage_id: 1, checks: {}, findings: [] } ], review_summary: {} }
            end
          puts({ is_error: false, result: payload.to_json }.to_json)
        RUBY

        described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        models_by_variant = File.readlines(models_log).map(&:chomp).to_h { |line| line.split(":", 2) }
        expect(models_by_variant["factcheck"]).to eq("sonnet")
        expect(models_by_variant["segmentation"]).to eq("opus")
        expect(models_by_variant["analysis"]).to eq("opus")
        expect(models_by_variant["localization"]).to eq("opus")
        expect(models_by_variant["editor"]).to eq("opus")
      end
    end

    it "saves invalid editor JSON raw instead of crashing the run, without affecting factcheck" do
      novel_dir = build_novel_dir(@root)
      korean_text = "챕터 1 한국어"
      write_korean_source(novel_dir, 1, korean_text)

      Dir.mktmpdir do |bin_dir|
        responses = pipeline_responses(korean_text: korean_text)
          .merge([ "", "editor" ] => { is_error: false, result: "not json at all" })
        bin = scripted_claude(bin_dir, responses)

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )
        r = results.first

        expect(r.editor_valid_json).to eq(false)
        expect(r.editor_error).to include("invalid JSON")

        chapter_dir = File.join(@output_dir, "chapter_1")
        expect(File.read(File.join(chapter_dir, "editor.raw.txt"))).to eq("not json at all")
        expect(File.exist?(File.join(chapter_dir, "editor.json"))).to eq(false)

        expect(r.factcheck_error).to be_nil
        expect(r.factcheck_valid_json).to eq(true)
      end
    end
  end
end
