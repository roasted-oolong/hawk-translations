require "rails_helper"
require "json"

RSpec.describe Pipeline::Ruby::VoiceCalibration do
  # Reuses the fake-`claude`-binary technique from
  # spec/services/pipeline/ruby/preread_runner_spec.rb — a real subprocess,
  # not a mock, so this spec exercises the real Pipeline::ClaudeCode call
  # path too.
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

  def build_novel_dir(chapter_file:)
    novel = create(:novel, directory_name: "test-novel-#{SecureRandom.hex(4)}")
    dir = File.join(@project_root, novel.directory_name)
    FileUtils.mkdir_p(File.join(dir, "bible"))
    FileUtils.mkdir_p(File.join(dir, "chapters"))
    File.write(File.join(dir, "chapters", "Chapter 1.txt"), chapter_file)
    dir
  end

  it "reads the translated chapter and voice_calibration.md, calls claude, and emits cards with no file writes" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(chapter_file: "Min-jun walked home in the rain.")
      File.write(File.join(novel_dir, "bible", "voice_calibration.md"), "## Passage 1 — Existing pattern\n\n> quote\n\n**The rule it demonstrates:** rule")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      create(:chapter, novel: novel, number: 1, status: "reviewed")
      @job = create(:translation_job, :voice_calibration, novel: novel, chapter_start: 1, chapter_end: 1)

      response = "=== NEW PATTERNS ===\n## Passage 2 — New\n*Chapter 1*\n\n> quote text\n\n**The rule it demonstrates:** a rule\n\n=== RETIREMENTS ===\nNOTHING TO REPORT\n"

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          stdin = STDIN.read
          raise "chapter text missing from prompt" unless stdin.include?("Min-jun walked home")
          raise "existing calibration doc missing from prompt" unless stdin.include?("Existing pattern")
          puts({ is_error: false, result: #{response.inspect} }.to_json)
        RUBY

        original_doc = File.read(File.join(novel_dir, "bible", "voice_calibration.md"))

        stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(true)
        expect(stderr).to eq("")

        payload = JSON.parse(stdout)
        expect(payload["cards"].length).to eq(1)
        expect(payload["cards"].first["card_type"]).to eq("new_pattern")
        expect(payload["cards"].first).not_to have_key("decision")

        expect(File.read(File.join(novel_dir, "bible", "voice_calibration.md"))).to eq(original_doc)
        expect(File.read("/tmp/hawk_job_#{@job.id}.progress")).to eq("100")
      end
    end
  end

  it "returns failure without raising when the claude call itself fails" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(chapter_file: "text")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      create(:chapter, novel: novel, number: 1, status: "reviewed")
      @job = create(:translation_job, :voice_calibration, novel: novel, chapter_start: 1, chapter_end: 1)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: true, subtype: "boom", result: "failed" }.to_json)
        RUBY

        _stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(false)
        expect(stderr).to include("cli_failure")
      end
    end
  end

  it "returns failure when no translated chapter file exists for the requested chapter" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = create(:novel, directory_name: "empty-novel-#{SecureRandom.hex(4)}")
      dir = File.join(@project_root, novel.directory_name)
      FileUtils.mkdir_p(File.join(dir, "chapters"))
      create(:chapter, novel: novel, number: 1, status: "reviewed")
      @job = create(:translation_job, :voice_calibration, novel: novel, chapter_start: 1, chapter_end: 1)

      _stdout, stderr, success = described_class.call(@job, config: config_for("/bin/true"))

      expect(success).to eq(false)
      expect(stderr).to include("No translated chapter file found")
    end
  end

  it "treats a missing voice_calibration.md as an empty document rather than an error" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(chapter_file: "text")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      create(:chapter, novel: novel, number: 1, status: "reviewed")
      @job = create(:translation_job, :voice_calibration, novel: novel, chapter_start: 1, chapter_end: 1)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          stdin = STDIN.read
          raise "should not include a Voice Calibration section" if stdin.include?("Voice Calibration")
          puts({ is_error: false, result: "=== NEW PATTERNS ===\\nNOTHING TO REPORT\\n\\n=== RETIREMENTS ===\\nNOTHING TO REPORT\\n" }.to_json)
        RUBY

        _stdout, _stderr, success = described_class.call(@job, config: config_for(bin))
        expect(success).to eq(true)
      end
    end
  end
end
