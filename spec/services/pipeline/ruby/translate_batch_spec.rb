require "rails_helper"
require "json"

RSpec.describe Pipeline::Ruby::TranslateBatch do
  # Reuses the fake-`claude`-binary technique from
  # spec/services/pipeline/ruby/preread_runner_spec.rb / voice_calibration_spec.rb —
  # a real subprocess, not a mock, so these specs exercise the real
  # Pipeline::ClaudeCode call path (and, via --mcp-config, the real
  # BridgeConfig-built argv) too.
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

  def build_novel_dir
    novel = create(:novel, directory_name: "test-novel-#{SecureRandom.hex(4)}")
    dir = File.join(@project_root, novel.directory_name)
    FileUtils.mkdir_p(File.join(dir, "bible"))
    FileUtils.mkdir_p(File.join(dir, "chapters"))
    [ novel, dir ]
  end

  def write_korean_source(dir, num, text)
    File.write(File.join(dir, "chapters", "Chapter #{num} (Korean).txt"), text)
  end

  # Echoes back is_error/result driven by a per-call Ruby lambda keyed on the
  # stdin content, so different chapters can be made to succeed or fail
  # within the same run.
  def scripted_claude(bin_dir, responses_by_marker)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      # force_encoding: Pipeline::ClaudeCode's allowlisted env has no
      # LANG/LC_ALL, so a bare STDIN.read here (unlike the real, compiled
      # `claude` binary) comes back US-ASCII-tagged and raises comparing
      # against a UTF-8 marker below.
      stdin = STDIN.read.force_encoding("UTF-8")
      responses = #{responses_by_marker.inspect}
      marker, response = responses.find { |m, _| stdin.include?(m) }
      raise "no scripted response matched stdin: \#{stdin[0,80]}" unless marker
      puts response.to_json
    RUBY
  end

  it "translates every chapter in range, writes atomically, reports progress, and returns success" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel, novel_dir = build_novel_dir
      write_korean_source(novel_dir, 1, "챕터 1 한국어 텍스트")
      write_korean_source(novel_dir, 2, "챕터 2 한국어 텍스트")
      @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 2)

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir, {
          "챕터 1" => { is_error: false, result: "Chapter one translated." },
          "챕터 2" => { is_error: false, result: "Chapter two translated." }
        })

        stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(true)
        expect(stderr).to eq("")
        expect(stdout).to include("2 chapter(s) translated.")

        expect(File.read(File.join(novel_dir, "chapters", "Chapter 1.txt"))).to eq("Chapter one translated.")
        expect(File.read(File.join(novel_dir, "chapters", "Chapter 2.txt"))).to eq("Chapter two translated.")
        expect(File.exist?(File.join(novel_dir, "chapters", "Chapter 1.txt.tmp"))).to eq(false)
        expect(File.exist?(File.join(novel_dir, "chapters", "Chapter 2.txt.tmp"))).to eq(false)

        expect(File.read("/tmp/hawk_job_#{@job.id}.progress")).to eq("100")
      end
    end
  end

  it "builds an mcp_config pointing at the real bridge script with the novel's directory name" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel, novel_dir = build_novel_dir
      write_korean_source(novel_dir, 1, "korean text")
      @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          mcp_config = JSON.parse(ARGV[ARGV.index("--mcp-config") + 1])
          server = mcp_config["mcpServers"]["hawk_skills"]
          raise "wrong novel dir" unless server["env"]["HAWK_BRIDGE_NOVEL_DIRECTORY_NAME"] == "#{novel.directory_name}"
          raise "command not absolute" unless server["command"].start_with?("/")
          raise "args not absolute" unless server["args"].first.start_with?("/")
          puts({ is_error: false, result: "translated" }.to_json)
        RUBY

        _stdout, _stderr, success = described_class.call(@job, config: config_for(bin))
        expect(success).to eq(true)
      end
    end
  end

  it "skips chapters with no Korean source file without treating it as a failure" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel, novel_dir = build_novel_dir
      write_korean_source(novel_dir, 1, "챕터 1")
      # No source file for chapter 2.
      @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 2)

      Dir.mktmpdir do |bin_dir|
        bin = fake_claude(bin_dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: false, result: "translated chapter one" }.to_json)
        RUBY

        stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(true)
        expect(stderr).to eq("")
        expect(stdout).to include("1 chapter(s) translated.")
        expect(stdout).to include("Skipped (missing source files): [2]")
        expect(File.exist?(File.join(novel_dir, "chapters", "Chapter 2.txt"))).to eq(false)
      end
    end
  end

  it "returns a benign success with nothing translated when every requested chapter is missing its source" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel, _novel_dir = build_novel_dir
      @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

      stdout, stderr, success = described_class.call(@job, config: config_for("/bin/true"))

      expect(success).to eq(true)
      expect(stderr).to eq("")
      expect(stdout).to include("Nothing to submit")
    end
  end

  it "continues past a recoverable per-chapter failure and reports it without a generic message" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel, novel_dir = build_novel_dir
      write_korean_source(novel_dir, 1, "챕터 1")
      write_korean_source(novel_dir, 2, "챕터 2")
      @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 2)

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir, {
          "챕터 1" => { is_error: true, subtype: "boom", result: "chapter 1 failed" },
          "챕터 2" => { is_error: false, result: "chapter two translated" }
        })

        stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(false)
        expect(stdout).to include("1 chapter(s) translated.")
        expect(stderr).to include("Chapter 1: cli_failure")
        expect(File.exist?(File.join(novel_dir, "chapters", "Chapter 1.txt"))).to eq(false)
        expect(File.read(File.join(novel_dir, "chapters", "Chapter 2.txt"))).to eq("chapter two translated")
      end
    end
  end

  it "stops starting further chapters once the job is cancelled mid-batch, keeping what already finished" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel, novel_dir = build_novel_dir
      write_korean_source(novel_dir, 1, "챕터 1")
      write_korean_source(novel_dir, 2, "챕터 2")
      @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 2)

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir, {
          "챕터 1" => { is_error: false, result: "chapter one translated" },
          "챕터 2" => { is_error: false, result: "chapter two translated" }
        })

        # Cancellation lands (e.g. via the controller, in another process)
        # after chapter 1's translation call has already returned
        # successfully — but before its feel-check call (translate_batch
        # runs both per chapter before checking @job.reload.cancelled?, so
        # the feel-check call still goes out; it just crashes harmlessly
        # here, same as it does for every other happy-path fake in this
        # file, since "chapter one translated" matches no scripted marker).
        original_call = Pipeline::ClaudeCode.method(:call)
        call_count = 0
        allow(Pipeline::ClaudeCode).to receive(:call) do |**kwargs|
          call_count += 1
          result = original_call.call(**kwargs)
          @job.cancel! if call_count == 1
          result
        end

        stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(call_count).to eq(2)
        expect(success).to eq(true)
        expect(stdout).to include("1 chapter(s) translated.")
        expect(stdout).to include("Not attempted (job was cancelled): [2]")
        expect(stderr).to include("job was cancelled")
        expect(File.read(File.join(novel_dir, "chapters", "Chapter 1.txt"))).to eq("chapter one translated")
        expect(File.exist?(File.join(novel_dir, "chapters", "Chapter 2.txt"))).to eq(false)
      end
    end
  end

  it "stops the batch after a fatal per-chapter failure instead of continuing to guaranteed-identical failures" do
    with_env("HAWK_PROJECT_ROOT" => @project_root) do
      novel, novel_dir = build_novel_dir
      write_korean_source(novel_dir, 1, "챕터 1")
      write_korean_source(novel_dir, 2, "챕터 2")
      write_korean_source(novel_dir, 3, "챕터 3")
      @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 3)

      Dir.mktmpdir do |bin_dir|
        # Self-kills with SIGKILL on the very first call — Pipeline::Subprocess
        # reports this as exit_code 137, which Pipeline::ClaudeCode buckets as
        # :killed (a FATAL_CATEGORY here, plausibly-OOM by convention).
        bin = fake_claude(bin_dir, "STDIN.read; Process.kill(:KILL, Process.pid)")

        stdout, stderr, success = described_class.call(@job, config: config_for(bin))

        expect(success).to eq(false)
        expect(stderr).to include("Chapter 1: killed")
        expect(stderr).to include("chapters [2, 3] were not attempted")
        expect(stdout).to include("Not attempted (batch stopped after a fatal error): [2, 3]")
      end
    end
  end

  describe "feel-check pass" do
    it "rewrites a segment the feel-check call flags as not reading naturally" do
      with_env("HAWK_PROJECT_ROOT" => @project_root) do
        novel, novel_dir = build_novel_dir
        write_korean_source(novel_dir, 1, "챕터 1")
        @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

        Dir.mktmpdir do |bin_dir|
          # Two calls per chapter now: the translation call (keyed on the
          # Korean marker, the user message translate_batch itself sends)
          # and the feel-check call (keyed on the "segment_id" JSON-shape
          # marker feel_check.rb's user message always contains).
          bin = scripted_claude(bin_dir, {
            "챕터 1" => { is_error: false, result: "Original clunky sentence." },
            "segment_id" => {
              is_error: false,
              result: { segments: [
                { segment_id: 1, reads_naturally: false, rewritten_text: "A much smoother sentence." }
              ] }.to_json
            }
          })

          _stdout, _stderr, success = described_class.call(@job, config: config_for(bin))

          expect(success).to eq(true)
          expect(File.read(File.join(novel_dir, "chapters", "Chapter 1.txt"))).to eq("A much smoother sentence.")
        end
      end
    end

    it "keeps the original translation when the feel-check call finds nothing to fix" do
      with_env("HAWK_PROJECT_ROOT" => @project_root) do
        novel, novel_dir = build_novel_dir
        write_korean_source(novel_dir, 1, "챕터 1")
        @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

        Dir.mktmpdir do |bin_dir|
          bin = scripted_claude(bin_dir, {
            "챕터 1" => { is_error: false, result: "Already natural sentence." },
            "segment_id" => {
              is_error: false,
              result: { segments: [ { segment_id: 1, reads_naturally: true } ] }.to_json
            }
          })

          _stdout, _stderr, success = described_class.call(@job, config: config_for(bin))

          expect(success).to eq(true)
          expect(File.read(File.join(novel_dir, "chapters", "Chapter 1.txt"))).to eq("Already natural sentence.")
        end
      end
    end

    it "keeps the original translation and reports it, rather than failing the chapter, when the feel-check call itself fails" do
      with_env("HAWK_PROJECT_ROOT" => @project_root) do
        novel, novel_dir = build_novel_dir
        write_korean_source(novel_dir, 1, "챕터 1")
        @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

        Dir.mktmpdir do |bin_dir|
          # No "segment_id" entry: scripted_claude's own fake script raises
          # on an unmatched call, which surfaces as a plain subprocess
          # failure (:cli_failure) to Pipeline::ClaudeCode — not a crash in
          # the test process.
          bin = scripted_claude(bin_dir, {
            "챕터 1" => { is_error: false, result: "Original sentence." }
          })

          stdout, _stderr, success = described_class.call(@job, config: config_for(bin))

          expect(success).to eq(true)
          expect(stdout).to include("Feel-check pass skipped, original translation kept as-is ([1])")
          expect(File.read(File.join(novel_dir, "chapters", "Chapter 1.txt"))).to eq("Original sentence.")
        end
      end
    end
  end

  describe "title finalize pass" do
    it "replaces the draft title with one translated against the finished, feel-check-polished body" do
      with_env("HAWK_PROJECT_ROOT" => @project_root) do
        novel, novel_dir = build_novel_dir
        write_korean_source(novel_dir, 1, "한국어 제목\n\n챕터 1 본문 텍스트")
        @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

        Dir.mktmpdir do |bin_dir|
          # Three calls per chapter now: translation (Korean marker),
          # feel-check ("segment_id" JSON-shape marker), and title finalize
          # ("# Korean Title" heading marker, which build_title_finalize_
          # user_message always contains).
          bin = scripted_claude(bin_dir, {
            "챕터 1" => { is_error: false, result: "Draft Title\n\nTranslated body text." },
            "segment_id" => {
              is_error: false,
              result: { segments: [ { segment_id: 1, reads_naturally: true } ] }.to_json
            },
            "# Korean Title" => { is_error: false, result: "Final Title" }
          })

          _stdout, _stderr, success = described_class.call(@job, config: config_for(bin))

          expect(success).to eq(true)
          expect(File.read(File.join(novel_dir, "chapters", "Chapter 1.txt")))
            .to eq("Final Title\n\nTranslated body text.")
        end
      end
    end

    it "keeps the draft title and reports it, rather than failing the chapter, when the title finalize call itself fails" do
      with_env("HAWK_PROJECT_ROOT" => @project_root) do
        novel, novel_dir = build_novel_dir
        write_korean_source(novel_dir, 1, "한국어 제목\n\n챕터 1 본문 텍스트")
        @job = create(:translation_job, :translate_batch, novel: novel, chapter_start: 1, chapter_end: 1)

        Dir.mktmpdir do |bin_dir|
          # No "# Korean Title" entry: scripted_claude's fake script raises
          # on an unmatched call, surfacing as :cli_failure — same technique
          # the feel-check failure test above uses.
          bin = scripted_claude(bin_dir, {
            "챕터 1" => { is_error: false, result: "Draft Title\n\nTranslated body text." },
            "segment_id" => {
              is_error: false,
              result: { segments: [ { segment_id: 1, reads_naturally: true } ] }.to_json
            }
          })

          stdout, _stderr, success = described_class.call(@job, config: config_for(bin))

          expect(success).to eq(true)
          expect(stdout).to include("Title finalize pass skipped, draft title kept as-is ([1])")
          expect(File.read(File.join(novel_dir, "chapters", "Chapter 1.txt")))
            .to eq("Draft Title\n\nTranslated body text.")
        end
      end
    end
  end
end
