require "rails_helper"
require "json"

RSpec.describe Pipeline::Ruby::PrereadRunner do
  # Reuses the fake-`claude`-binary technique from
  # spec/services/pipeline/claude_code_spec.rb — a real subprocess, not a
  # mock, so this spec exercises the real Pipeline::ClaudeCode call path too.
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

  def five_section_response(characters: "NOTHING TO ADD", story: "NOTHING TO ADD")
    "=== CHARACTERS ===\n#{characters}\n\n" \
    "=== LOCATIONS ===\nNOTHING TO ADD\n\n" \
    "=== TERMINOLOGY ===\nNOTHING TO ADD\n\n" \
    "=== CULTURAL PHRASES ===\nNOTHING TO ADD\n\n" \
    "=== STORY ===\n#{story}\n"
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

  def build_novel_dir(chapter_files: {})
    novel = create(:novel, directory_name: "test-novel-#{SecureRandom.hex(4)}")
    dir = File.join(@project_root, novel.directory_name)
    FileUtils.mkdir_p(File.join(dir, "bible"))
    FileUtils.mkdir_p(File.join(dir, "chapters"))
    chapter_files.each { |name, content| File.write(File.join(dir, "chapters", name), content) }
    novel
  end

  it "runs one batch per chapter, writing parsed findings and advancing the progress file" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = build_novel_dir(chapter_files: { "ch1_korean" => "one", "ch2_korean" => "two" })
      @job = create(:translation_job, novel: novel, job_type: "preread", chapter_start: 1, chapter_end: 2)

      Dir.mktmpdir do |bin_dir|
        # The second call only succeeds if its prompt already contains "Nova"
        # — proving the bible is re-read fresh before each batch, not built
        # once from a stale pre-loop snapshot.
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          stdin = STDIN.read
          if stdin.include?("CHAPTER 2") && !stdin.include?("Nova")
            puts({ is_error: true, subtype: "stale_bible_snapshot", result: "expected Nova in chapter 2 prompt" }.to_json)
          else
            puts({ is_error: false, result: #{five_section_response(characters: "## Nova (노바) — English\\n- Role: idol").inspect} }.to_json)
          end
        RUBY

        stdout, stderr, success = described_class.call(
          @job,
          discovery: ->(dir) { Pipeline::Ruby::PrereadRunner::ChapterDiscovery.find_untranslated_chapters(dir) },
          batch_size: 1,
          config: config_for(bin)
        )

        expect(success).to eq(true)
        expect(stderr).to eq("")
        expect(stdout).to include("Chapters 1").and include("Chapters 2")

        characters_content = File.read(File.join(@project_root, novel.directory_name, "bible/characters.md"))
        expect(characters_content.scan("## Nova").length).to eq(1)

        expect(File.read("/tmp/hawk_job_#{@job.id}.progress")).to eq("100")
      end
    end
  end

  it "filters the job's chapter range through the given discovery predicate, skipping unavailable chapters" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = build_novel_dir(chapter_files: {
        "ch1_korean" => "one", "ch2_korean" => "two", "ch3_korean" => "three", "Chapter 3.txt" => "translated"
      })
      @job = create(:translation_job, novel: novel, job_type: "preread", chapter_start: 1, chapter_end: 3)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: false, result: #{five_section_response.inspect} }.to_json)
        RUBY

        stdout, _stderr, success = described_class.call(
          @job,
          discovery: ->(dir) { Pipeline::Ruby::PrereadRunner::ChapterDiscovery.find_untranslated_chapters(dir) },
          batch_size: 10,
          config: config_for(bin)
        )

        expect(success).to eq(true)
        expect(stdout).to include("Chapters 1, 2")
        expect(stdout).to include("Skipping chapters not found or already translated: [3]")
      end
    end
  end

  it "includes an already-translated chapter when given bible_build's discovery predicate instead" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = build_novel_dir(chapter_files: {
        "ch1_korean" => "one", "ch2_korean" => "two", "ch3_korean" => "three", "Chapter 3.txt" => "translated"
      })
      @job = create(:translation_job, :bible_build, novel: novel, chapter_start: 1, chapter_end: 3)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: false, result: #{five_section_response.inspect} }.to_json)
        RUBY

        stdout, _stderr, success = described_class.call(
          @job,
          discovery: ->(dir) { Pipeline::Ruby::PrereadRunner::ChapterDiscovery.find_all_korean_chapters(dir) },
          batch_size: 10,
          config: config_for(bin)
        )

        expect(success).to eq(true)
        expect(stdout).to include("Chapters 1, 2, 3")
        expect(stdout).not_to include("Skipping")
      end
    end
  end

  it "stops the batch loop and returns failure when a batch's claude call fails, keeping earlier batches' writes" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = build_novel_dir(chapter_files: { "ch1_korean" => "one", "ch2_korean" => "two" })
      @job = create(:translation_job, novel: novel, job_type: "preread", chapter_start: 1, chapter_end: 2)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          stdin = STDIN.read
          if stdin.include?("CHAPTER 2")
            puts({ is_error: true, subtype: "boom", result: "failed" }.to_json)
          else
            puts({ is_error: false, result: #{five_section_response(characters: "## Nova (노바) — English\\n- Role: idol").inspect} }.to_json)
          end
        RUBY

        stdout, stderr, success = described_class.call(
          @job,
          discovery: ->(dir) { Pipeline::Ruby::PrereadRunner::ChapterDiscovery.find_untranslated_chapters(dir) },
          batch_size: 1,
          config: config_for(bin)
        )

        expect(success).to eq(false)
        expect(stderr).to include("chapters [2]")
        expect(stdout).to include("Chapters 1")

        characters_content = File.read(File.join(@project_root, novel.directory_name, "bible/characters.md"))
        expect(characters_content).to include("## Nova")
      end
    end
  end

  it "fails closed when a response is missing all five section markers" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = build_novel_dir(chapter_files: { "ch1_korean" => "one" })
      @job = create(:translation_job, novel: novel, job_type: "preread", chapter_start: 1, chapter_end: 1)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: false, result: "just a paragraph, no structure" }.to_json)
        RUBY

        _stdout, stderr, success = described_class.call(
          @job,
          discovery: ->(dir) { Pipeline::Ruby::PrereadRunner::ChapterDiscovery.find_untranslated_chapters(dir) },
          batch_size: 1,
          config: config_for(bin)
        )

        expect(success).to eq(false)
        expect(stderr).to include("missing section markers")
      end
    end
  end

  it "returns success with no batches run when no chapters match the discovery predicate" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = build_novel_dir(chapter_files: {})
      @job = create(:translation_job, novel: novel, job_type: "preread", chapter_start: 1, chapter_end: 1)

      stdout, stderr, success = described_class.call(
        @job,
        discovery: ->(dir) { Pipeline::Ruby::PrereadRunner::ChapterDiscovery.find_untranslated_chapters(dir) },
        batch_size: 2,
        config: config_for("/bin/true")
      )

      expect(success).to eq(true)
      expect(stderr).to eq("")
      expect(stdout).to include("No chapters to process.")
    end
  end
end
