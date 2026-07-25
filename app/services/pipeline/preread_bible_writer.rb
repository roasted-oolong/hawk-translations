# ---------------------------------------------------------------------------
# Pipeline::PrereadBibleWriter
#
# Ruby port of src/preread/bible_writer.py's append_to_bible/
# write_batch_findings, rebuilt on Pipeline::BibleFileEditor#append_block
# instead of direct File I/O — the writer owns batch parsing, grouping by
# target file, and BibleUtils.heading_key-based dedup; BibleFileEditor owns
# the lock/fresh-read/atomic-write mechanics underneath it. Dedup is always
# computed against the freshly-read file content BibleFileEditor hands to
# the block, never a snapshot taken before the lock was acquired.
# ---------------------------------------------------------------------------
module Pipeline
  class PrereadBibleWriter
    SECTION_TO_FILE = {
      characters:        "bible/characters.md",
      locations:         "bible/locations.md",
      terminology:       "bible/terminology.md",
      cultural_phrases:  "bible/cultural_phrases.md",
      story:             "bible/story.md"
    }.freeze

    def initialize(novel_dir, editor: Pipeline::BibleFileEditor.new)
      @novel_dir = novel_dir
      @editor    = editor
    end

    # parsed_sections: hash of section key (see SECTION_TO_FILE) => content
    # string, as produced by PrereadRunner::ResponseParser. Returns a hash of
    # section key => :written | :no_new_entries | :empty, for the caller to
    # fold into a progress/log line.
    def write_batch(parsed_sections)
      SECTION_TO_FILE.each_key.to_h do |key|
        content = parsed_sections[key]
        [ key, (content && !content.strip.empty?) ? append_to_bible(key, content) : :empty ]
      end
    end

    private

    def append_to_bible(section_key, content)
      file = File.join(@novel_dir, SECTION_TO_FILE.fetch(section_key))
      entries = split_into_entries(content)

      result = @editor.append_block(file) do |fresh|
        existing_keys = Pipeline::BibleUtils.extract_heading_keys(fresh)
        new_entries = entries.reject { |entry| duplicate?(entry, existing_keys) }

        next Pipeline::BibleFileEditor::SKIP if new_entries.empty?

        combined  = new_entries.join("\n\n")
        separator = fresh.strip.empty? ? "" : "\n\n---\n\n"
        "#{fresh.rstrip}#{separator}#{combined}\n"
      end

      result == Pipeline::BibleFileEditor::SKIP ? :no_new_entries : :written
    end

    # An entry with no ## heading (plain prose, e.g. a STORY update) is never
    # a duplicate — only heading-keyed entries participate in dedup.
    def duplicate?(entry, existing_keys)
      entry_keys = Pipeline::BibleUtils.extract_heading_keys(entry)
      return false if entry_keys.empty?
      !(entry_keys & existing_keys).empty?
    end

    def split_into_entries(content)
      content.split(/(?=^## )/).map(&:strip).reject(&:empty?)
    end
  end
end
