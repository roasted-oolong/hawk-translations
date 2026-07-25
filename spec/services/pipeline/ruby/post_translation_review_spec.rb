require "rails_helper"
require "json"

RSpec.describe Pipeline::Ruby::PostTranslationReview do
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

  def three_section_response(new_entries: "NOTHING TO ADD", proposed_edits: "NOTHING TO ADD", story_updates: "NOTHING TO ADD")
    "=== NEW ENTRIES ===\n#{new_entries}\n\n" \
    "=== PROPOSED EDITS ===\n#{proposed_edits}\n\n" \
    "=== STORY UPDATES ===\n#{story_updates}\n"
  end

  it "reads the translated chapter and bible files, calls claude, and emits cards with a bible_revision fingerprint" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(chapter_file: "Min-jun walked home in the rain.")
      File.write(File.join(novel_dir, "bible", "characters.md"), "## Existing Char — English\n- Role: villager\n")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create(:translation_job, :post_translation_review, novel: novel, chapter_start: 1, chapter_end: 1)

      response = three_section_response(new_entries: "### characters.md\n## New Girl — English\n- Role: rival\n")

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          stdin = STDIN.read
          raise "chapter text missing from prompt" unless stdin.include?("Min-jun walked home")
          raise "existing bible content missing from prompt" unless stdin.include?("Existing Char")
          puts({ is_error: false, result: #{response.inspect} }.to_json)
        RUBY

        stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(true)
        expect(stderr).to eq("")

        payload = JSON.parse(stdout)
        expect(payload["cards"].length).to eq(1)
        expect(payload["cards"].first["card_type"]).to eq("new_entry")
        expect(payload["bible_revision"]["characters"]).to eq(Digest::SHA256.hexdigest(File.read(File.join(novel_dir, "bible", "characters.md"))))

        expect(File.read("/tmp/hawk_job_#{@job.id}.progress")).to eq("100")
      end
    end
  end

  it "returns failure without writing anything when the claude call itself fails" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(chapter_file: "text")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create(:translation_job, :post_translation_review, novel: novel, chapter_start: 1, chapter_end: 1)

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

  it "fails closed when the response is missing its section markers" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel_dir = build_novel_dir(chapter_file: "text")
      novel = Novel.find_by!(directory_name: File.basename(novel_dir))
      @job = create(:translation_job, :post_translation_review, novel: novel, chapter_start: 1, chapter_end: 1)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: false, result: "just unstructured prose" }.to_json)
        RUBY

        _stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(false)
        expect(stderr).to include("missing_markers")
      end
    end
  end

  it "returns failure when no translated chapter file exists for the requested chapter" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel = create(:novel, directory_name: "empty-novel-#{SecureRandom.hex(4)}")
      dir = File.join(@project_root, novel.directory_name)
      FileUtils.mkdir_p(File.join(dir, "chapters"))
      @job = create(:translation_job, :post_translation_review, novel: novel, chapter_start: 1, chapter_end: 1)

      _stdout, stderr, success = described_class.call(@job, config: config_for("/bin/true"))

      expect(success).to eq(false)
      expect(stderr).to include("No translated chapter file found")
    end
  end
end
