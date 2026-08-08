require "rails_helper"
require "json"

RSpec.describe Pipeline::Ruby::ChapterQa do
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def config_for(claude_bin)
    TranslationConfig.from_env("PATH" => "", "CLAUDE_BIN" => claude_bin)
  end

  def with_env(vars)
    original = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  around do |example|
    Dir.mktmpdir do |root|
      @project_root = root
      example.run
    end
  end

  after do
    FileUtils.rm_f("/tmp/hawk_job_#{@job.id}.progress") if @job
  end

  def build_novel_dir(korean:, english:)
    novel = create(:novel, directory_name: "test-novel-#{SecureRandom.hex(4)}")
    create(:chapter, novel: novel, number: 1, status: "translated")
    dir = File.join(@project_root, novel.directory_name)
    FileUtils.mkdir_p(File.join(dir, "bible"))
    FileUtils.mkdir_p(File.join(dir, "chapters"))
    File.write(File.join(dir, "chapters", "Chapter 1 (Korean).txt"), korean)
    File.write(File.join(dir, "chapters", "Chapter 1.txt"), english)
    dir
  end

  # Distinguishes the two calls by the one structural difference between
  # their system prompts: only factcheck's asks for korean_context (editor
  # is deliberately Korean-blind and never mentions it).
  def scripted_claude(bin_dir, factcheck_response:, editor_response:, models_log: nil, mcp_log: nil)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      STDIN.read
      prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
      prompt = File.read(prompt_path)
      variant = prompt.include?("korean_context") ? "factcheck" : "editor"
      #{"File.open(#{models_log.inspect}, 'a') { |f| f.puts \"\#{variant}:\#{ARGV[ARGV.index('--model') + 1]}\" }" if models_log}
      #{"File.open(#{mcp_log.inspect}, 'a') { |f| f.puts \"\#{variant}:\#{ARGV.include?('--mcp-config')}\" }" if mcp_log}
      response = variant == "factcheck" ? #{factcheck_response.to_json.inspect} : #{editor_response.to_json.inspect}
      puts response
    RUBY
  end

  def create_qa_job(novel)
    create(:translation_job, :chapter_qa, novel: novel, chapter_start: 1, chapter_end: 1)
  end

  it "runs factcheck then editor and merges both into a flat, tagged suggestions array" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(korean: "그는 조용히 웃었다.", english: "He smiled quietly.")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create_qa_job(novel)

      factcheck_payload = { suggestions: [
        { quote: "smiled quietly", issue: "tone mismatch", suggested_revision: "grinned",
          severity: "advisory", korean_context: "조용히 웃었다" }
      ] }
      editor_payload = { suggestions: [
        { quote: "He smiled", issue: "flat opener", suggested_revision: "He grinned", severity: "strong" }
      ] }

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir,
          factcheck_response: { is_error: false, result: factcheck_payload.to_json },
          editor_response:    { is_error: false, result: editor_payload.to_json })

        stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(true)
        expect(stderr).to eq("")

        payload = JSON.parse(stdout)
        expect(payload["suggestions"].size).to eq(2)

        factcheck_card = payload["suggestions"].find { |s| s["source"] == "factcheck" }
        expect(factcheck_card["quote"]).to eq("smiled quietly")
        expect(factcheck_card["suggested_revision"]).to eq("grinned")
        expect(factcheck_card["severity"]).to eq("advisory")
        expect(factcheck_card["korean_context"]).to eq("조용히 웃었다")
        expect(factcheck_card["status"]).to eq("pending")
        expect(factcheck_card["id"]).to be_present

        editor_card = payload["suggestions"].find { |s| s["source"] == "editor" }
        expect(editor_card["quote"]).to eq("He smiled")
        expect(editor_card["suggested_revision"]).to eq("He grinned")
        expect(editor_card["status"]).to eq("pending")
        expect(editor_card["id"]).to be_present
        expect(editor_card["id"]).not_to eq(factcheck_card["id"])

        expect(File.read("/tmp/hawk_job_#{@job.id}.progress")).to eq("100")
      end
    end
  end

  it "orders merged suggestions by where their quote sits in the chapter, not by which pass found them" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      # The editor pass's quote sits earlier in the text than either factcheck
      # quote — a naive factcheck-then-editor concat would surface it last,
      # which is exactly what makes the reviewer's "next suggestion" jump
      # backward/forward across the chapter instead of moving in reading order.
      english = "He grinned. Later, he smiled quietly. At the end, he sighed."
      novel_dir = build_novel_dir(korean: "그는 웃었다.", english: english)
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create_qa_job(novel)

      factcheck_payload = { suggestions: [
        { quote: "he sighed", issue: "wrong emotion", suggested_revision: "he wept",
          severity: "advisory", korean_context: "그는 울었다" },
        { quote: "smiled quietly", issue: "tone mismatch", suggested_revision: "chuckled",
          severity: "advisory", korean_context: "조용히 웃었다" }
      ] }
      editor_payload = { suggestions: [
        { quote: "He grinned", issue: "flat opener", suggested_revision: "He beamed", severity: "strong" }
      ] }

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir,
          factcheck_response: { is_error: false, result: factcheck_payload.to_json },
          editor_response:    { is_error: false, result: editor_payload.to_json })

        stdout, _stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(true)
        quotes_in_order = JSON.parse(stdout)["suggestions"].map { |s| s["quote"] }
        expect(quotes_in_order).to eq([ "He grinned", "smiled quietly", "he sighed" ])
      end
    end
  end

  it "uses factcheck_model for the factcheck call and translation_model for the editor call" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(korean: "한국어", english: "English text.")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create_qa_job(novel)

      Dir.mktmpdir do |bin_dir|
        models_log = File.join(bin_dir, "models.log")
        bin = scripted_claude(bin_dir,
          factcheck_response: { is_error: false, result: { suggestions: [] }.to_json },
          editor_response:    { is_error: false, result: { suggestions: [] }.to_json },
          models_log: models_log)

        config = TranslationConfig.from_env("PATH" => "", "CLAUDE_BIN" => bin, "TRANSLATION_MODEL" => "opus")
        _stdout, _stderr, success = described_class.call(@job, config: config)

        expect(success).to eq(true)
        models_by_variant = File.readlines(models_log).map(&:chomp).to_h { |line| line.split(":", 2) }
        expect(models_by_variant["factcheck"]).to eq("sonnet")
        expect(models_by_variant["editor"]).to eq("opus")
      end
    end
  end

  it "gives the factcheck call the bible_lookup MCP tool but keeps the editor call tool-free" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(korean: "한국어", english: "English text.")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create_qa_job(novel)

      Dir.mktmpdir do |bin_dir|
        mcp_log = File.join(bin_dir, "mcp.log")
        bin = scripted_claude(bin_dir,
          factcheck_response: { is_error: false, result: { suggestions: [] }.to_json },
          editor_response:    { is_error: false, result: { suggestions: [] }.to_json },
          mcp_log: mcp_log)

        _stdout, _stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(true)
        mcp_by_variant = File.readlines(mcp_log).map(&:chomp).to_h { |line| line.split(":", 2) }
        expect(mcp_by_variant["factcheck"]).to eq("true")
        expect(mcp_by_variant["editor"]).to eq("false")
      end
    end
  end

  it "drops a finding whose quote is not an actual substring of the checked text" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(korean: "한국어", english: "The real sentence.")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create_qa_job(novel)

      factcheck_payload = { suggestions: [
        { quote: "a sentence that never appears", issue: "bad anchor", suggested_revision: "x", severity: "advisory" },
        { quote: "real sentence", issue: "fine", suggested_revision: "actual sentence", severity: "advisory" }
      ] }

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir,
          factcheck_response: { is_error: false, result: factcheck_payload.to_json },
          editor_response:    { is_error: false, result: { suggestions: [] }.to_json })

        stdout, _stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(true)
        suggestions = JSON.parse(stdout)["suggestions"]
        expect(suggestions.size).to eq(1)
        expect(suggestions.first["quote"]).to eq("real sentence")
      end
    end
  end

  it "short-circuits before the editor call when factcheck itself fails" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(korean: "한국어", english: "English text.")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create_qa_job(novel)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: true, subtype: "boom", result: "failed" }.to_json)
        RUBY

        _stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(false)
        expect(stderr).to include("factcheck:")
        expect(stderr).to include("cli_failure")
        expect(File.exist?("/tmp/hawk_job_#{@job.id}.progress")).to eq(false)
      end
    end
  end

  it "fails after factcheck succeeds when the editor call itself fails" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(korean: "한국어", english: "English text.")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create_qa_job(novel)

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir,
          factcheck_response: { is_error: false, result: { suggestions: [] }.to_json },
          editor_response:    { is_error: true, subtype: "boom", result: "failed" })

        _stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(false)
        expect(stderr).to include("editor:")
        expect(File.read("/tmp/hawk_job_#{@job.id}.progress")).to eq("50")
      end
    end
  end

  it "fails closed on invalid JSON from either pass instead of crashing" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(korean: "한국어", english: "English text.")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create_qa_job(novel)

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir,
          factcheck_response: { is_error: false, result: "not json at all" },
          editor_response:    { is_error: false, result: { suggestions: [] }.to_json })

        _stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(false)
        expect(stderr).to include("factcheck:")
        expect(stderr).to include("invalid JSON")
      end
    end
  end

  it "returns failure without calling claude when no translated chapter file exists" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = create(:novel, directory_name: "empty-novel-#{SecureRandom.hex(4)}")
      create(:chapter, novel: novel, number: 1, status: "translated")
      dir = File.join(@project_root, novel.directory_name)
      FileUtils.mkdir_p(File.join(dir, "chapters"))
      File.write(File.join(dir, "chapters", "Chapter 1 (Korean).txt"), "한국어")
      @job = create_qa_job(novel)

      _stdout, stderr, success = described_class.call(@job, config: config_for("/bin/true"))

      expect(success).to eq(false)
      expect(stderr).to include("No translated chapter file found")
    end
  end

  it "returns failure without calling claude when no Korean source file exists" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = create(:novel, directory_name: "no-korean-novel-#{SecureRandom.hex(4)}")
      create(:chapter, novel: novel, number: 1, status: "translated")
      dir = File.join(@project_root, novel.directory_name)
      FileUtils.mkdir_p(File.join(dir, "chapters"))
      File.write(File.join(dir, "chapters", "Chapter 1.txt"), "English text.")
      @job = create_qa_job(novel)

      _stdout, stderr, success = described_class.call(@job, config: config_for("/bin/true"))

      expect(success).to eq(false)
      expect(stderr).to include("No Korean source file found")
    end
  end
end
