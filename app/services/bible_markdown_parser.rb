class BibleMarkdownParser
  CATEGORIES = %i[characters locations terminology cultural_phrases story].freeze

  FILE_MAP = {
    characters:       "characters.md",
    locations:        "locations.md",
    terminology:      "terminology.md",
    cultural_phrases: "cultural_phrases.md",
    story:            "story.md",
  }.freeze

  COMPARABLE_FIELDS = {
    characters:       %i[name korean_name aliases role physical_description speech_pattern
                         honorifics_used_toward honorifics_they_use relationships
                         first_appearance_chapter notes],
    locations:        %i[name korean_name significance first_appearance_chapter notes],
    terminology:      %i[term korean_term definition usage_notes first_appearance_chapter notes],
    cultural_phrases: %i[phrase korean_phrase literal_translation intended_meaning context
                         established_translation first_appearance_chapter notes],
    story:            %i[title content category],
  }.freeze

  STORY_CATEGORY_PATTERNS = [
    [ /main.?plot/i,  "main_plot"   ],
    [ /subplot/i,     "subplot"     ],
    [ /watch.?list/i, "watch_list"  ],
    [ /theme|motif/i, "theme"       ],
  ].freeze

  def initialize(novel)
    @novel = novel
  end

  def pending_entries
    return empty_result if bible_dir.nil?

    CATEGORIES.each_with_object({}) do |cat, h|
      h[cat] = filter_pending(cat, parse_file(cat))
    end
  end

  private

  def empty_result
    CATEGORIES.each_with_object({}) { |cat, h| h[cat] = [] }
  end

  def bible_dir
    root = ENV.fetch("HAWK_PROJECT_ROOT", "")
    return nil if root.blank? || @novel.directory_name.blank?
    File.join(root, @novel.directory_name, "bible")
  end

  # ---------------------------------------------------------------------------
  # File I/O
  # ---------------------------------------------------------------------------

  def parse_file(cat)
    path = File.join(bible_dir, FILE_MAP[cat])
    content = File.read(path, encoding: "UTF-8")
    content.encode!("UTF-8", invalid: :replace, undef: :replace, replace: "")
    parse_entries(cat, content)
  rescue Errno::ENOENT, Errno::EACCES
    []
  end

  # ---------------------------------------------------------------------------
  # Entry splitting
  # ---------------------------------------------------------------------------

  def parse_entries(cat, content)
    content
      .split(/\n(?=## )/)
      .map(&:strip)
      .select { |chunk| chunk.start_with?("## ") }
      .map { |chunk| parse_chunk(cat, chunk) }
      .compact
  end

  def parse_chunk(cat, chunk)
    lines = chunk.split("\n")
    heading = lines.shift&.strip
    return nil unless heading&.start_with?("## ")

    cat == :story ? parse_story_entry(heading, lines) : parse_structured_entry(cat, heading, lines)
  end

  # ---------------------------------------------------------------------------
  # Heading + field parsing
  # ---------------------------------------------------------------------------

  def parse_heading(heading)
    m = heading.match(/\A## (.+?)\s*(?:\((.+)\))?\s*\z/)
    return [ nil, nil ] unless m

    [ m[1].strip, m[2]&.strip ]
  end

  def parse_fields(lines)
    lines.each_with_object({}) do |line, h|
      m = line.match(/\A-\s+(.+?):\s*(.*)\z/)
      next unless m

      key   = m[1].strip.downcase
      value = m[2].strip
      h[key] = value unless value.empty? || value.match?(/\A\[.*\]\z/)
    end
  end

  def extract_chapter(value)
    value.to_s.scan(/\d+/).first&.to_i
  end

  def join_notes(*parts)
    parts.flatten.compact_blank.join("\n").presence
  end

  # ---------------------------------------------------------------------------
  # Per-category parsers
  # ---------------------------------------------------------------------------

  def parse_structured_entry(cat, heading, lines)
    name, korean = parse_heading(heading)
    return nil unless name.present?

    fields = parse_fields(lines)

    case cat
    when :characters       then parse_character(name, korean, fields)
    when :locations        then parse_location(name, korean, fields)
    when :terminology      then parse_terminology(name, korean, fields)
    when :cultural_phrases then parse_cultural_phrase(name, korean, fields)
    end
  end

  def parse_character(name, korean, f)
    speech = join_notes(f["speech pattern"], f["dialogue cues"])
    notes  = join_notes(
      f["notes"],
      f["story bible reference"].presence&.then { "Bible ref: #{_1}" }
    )

    {
      name:                     name,
      korean_name:              f["korean name"].presence || korean,
      aliases:                  f["aliases/titles"].presence,
      role:                     f["role"].presence,
      physical_description:     f["physical description"].presence,
      speech_pattern:           speech,
      honorifics_used_toward:   f["honorifics used toward them"].presence,
      honorifics_they_use:      f["honorifics they use toward others"].presence,
      relationships:            f["relationships"].presence,
      first_appearance_chapter: extract_chapter(f["first appearance"]),
      notes:                    notes,
      korean_key:               f["korean name"].presence || korean || name,
    }.compact
  end

  def parse_location(name, korean, f)
    notes = f["romanisation"].presence&.then { "Romanisation: #{_1}" }

    {
      name:                     name,
      korean_name:              f["korean name"].presence || korean,
      significance:             f["significance"].presence,
      first_appearance_chapter: extract_chapter(f["first appearance"]),
      notes:                    notes,
      korean_key:               f["korean name"].presence || korean || name,
    }.compact
  end

  def parse_terminology(name, korean, f)
    notes = join_notes(
      f["notes"],
      f["category"].presence&.then { "Category: #{_1}" },
      f["story bible reference"].presence&.then { "Bible ref: #{_1}" }
    )

    {
      term:                     name,
      korean_term:              f["korean term"].presence || korean,
      definition:               f["definition"].presence,
      usage_notes:              f["usage notes"].presence,
      first_appearance_chapter: extract_chapter(f["first appearance"]),
      notes:                    notes,
      korean_key:               f["korean term"].presence || korean || name,
    }.compact
  end

  def parse_cultural_phrase(name, korean, f)
    tn = join_notes(
      f["t/n written"].presence&.then { "T/N written: #{_1}" },
      f["t/n text"].presence&.then   { "T/N text: #{_1}" }
    )
    notes = join_notes(f["notes"], tn)

    {
      phrase:                   name,
      korean_phrase:            f["korean phrase"].presence || korean,
      literal_translation:      f["literal translation"].presence,
      intended_meaning:         f["intended meaning"].presence,
      context:                  f["context"].presence,
      established_translation:  f["established translation"].presence,
      first_appearance_chapter: extract_chapter(f["first appearance"]),
      notes:                    notes,
      korean_key:               f["korean phrase"].presence || korean || name,
    }.compact
  end

  def parse_story_entry(heading, lines)
    title   = heading.sub(/\A## /, "").strip
    content = lines.reject { |l| l.strip == "---" }.join("\n").strip

    return nil if content.blank?

    {
      title:      title,
      content:    content,
      category:   infer_story_category(title),
      korean_key: title,
    }.compact
  end

  def infer_story_category(title)
    STORY_CATEGORY_PATTERNS.each { |pat, cat| return cat if title.match?(pat) }
    "world_building"
  end

  # ---------------------------------------------------------------------------
  # Classification — new entries pass through; existing ones carry a diff
  # ---------------------------------------------------------------------------

  def filter_pending(cat, entries)
    dismissed = dismissed_keys
    fields    = COMPARABLE_FIELDS[cat]
    case cat
    when :characters
      by_korean = @novel.bible_characters.index_by(&:korean_name)
      by_name   = @novel.bible_characters.index_by(&:name)
      entries.filter_map { |e|
        next if dismissed.include?("#{cat}:#{e[:korean_key]}")
        record = by_korean[e[:korean_key]] || by_name[e[:name]]
        classify_entry(e, record, fields)
      }
    when :locations
      by_korean = @novel.bible_locations.index_by(&:korean_name)
      by_name   = @novel.bible_locations.index_by(&:name)
      entries.filter_map { |e|
        next if dismissed.include?("#{cat}:#{e[:korean_key]}")
        record = by_korean[e[:korean_key]] || by_name[e[:name]]
        classify_entry(e, record, fields)
      }
    when :terminology
      by_korean = @novel.bible_terminologies.index_by(&:korean_term)
      by_name   = @novel.bible_terminologies.index_by(&:term)
      entries.filter_map { |e|
        next if dismissed.include?("#{cat}:#{e[:korean_key]}")
        record = by_korean[e[:korean_key]] || by_name[e[:term]]
        classify_entry(e, record, fields)
      }
    when :cultural_phrases
      by_korean = @novel.bible_cultural_phrases.index_by(&:korean_phrase)
      by_name   = @novel.bible_cultural_phrases.index_by(&:phrase)
      entries.filter_map { |e|
        next if dismissed.include?("#{cat}:#{e[:korean_key]}")
        record = by_korean[e[:korean_key]] || by_name[e[:phrase]]
        classify_entry(e, record, fields)
      }
    when :story
      by_title = @novel.bible_story_entries.index_by(&:title)
      entries.filter_map { |e|
        next if dismissed.include?("#{cat}:#{e[:korean_key]}")
        record = by_title[e[:title]]
        classify_entry(e, record, fields)
      }
    else
      entries.map { |e| e.merge(is_existing: false) }
    end
  end

  def dismissed_keys
    @dismissed_keys ||= JSON.parse(@novel.preread_dismissed_keys || "[]")
  rescue JSON::ParserError
    []
  end

  def classify_entry(entry, record, fields)
    return entry.merge(is_existing: false) if record.nil?

    changes = compute_field_changes(entry, record, fields)
    return nil if changes.empty?

    entry.merge(is_existing: true, existing_id: record.id, field_changes: changes)
  end

  def compute_field_changes(entry, record, fields)
    fields.each_with_object({}) do |field, h|
      new_val = normalize_compare(entry[field])
      old_val = normalize_compare(record.respond_to?(field) ? record.public_send(field) : nil)
      next if new_val == old_val
      h[field] = { was: old_val, now: new_val }
    end
  end

  def normalize_compare(val)
    return nil if val.nil?
    val.to_s.strip.presence
  end
end
