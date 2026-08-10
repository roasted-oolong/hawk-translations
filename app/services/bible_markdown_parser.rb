class BibleMarkdownParser
  CATEGORIES = %i[characters locations terminology cultural_phrases story].freeze

  FILE_MAP = {
    characters:       "characters.md",
    locations:        "locations.md",
    terminology:      "terminology.md",
    cultural_phrases: "cultural_phrases.md",
    story:            "story.md",
  }.freeze

  def initialize(novel)
    @novel = novel
    @matcher = Pipeline::BibleEntryMatcher.new(novel)
  end

  def pending_entries
    return empty_result if bible_dir.nil?

    CATEGORIES.each_with_object({}) do |cat, h|
      h[cat] = @matcher.classify_parsed(cat, parse_file(cat))
    end
  end

  # Just the counts — shared by ChapterReviewController#tab (initial render)
  # and TranslationJob's preread broadcast (push update), so both compute
  # the "N pending" card from one place rather than re-deriving it twice.
  def pending_breakdown
    by_category = pending_entries.transform_values(&:size)
    { total: by_category.values.sum, by_category: by_category }
  end

  def dismissed_entries
    return empty_result if bible_dir.nil?

    dismissed = dismissed_keys.to_set

    CATEGORIES.each_with_object({}) do |cat, h|
      h[cat] = parse_file(cat).select { |e| dismissed.include?("#{cat}:#{e[:korean_key]}") }
    end
  end

  def dismissed_entries_for(cat)
    return [] if bible_dir.nil?

    dismissed = dismissed_keys.to_set
    parse_file(cat).select do |e|
      dismissed.include?("#{cat}:#{e[:korean_key]}") && @matcher.matching_record(cat, e).nil?
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
  # File I/O — reads bible/*.md and hands the raw content to the matcher.
  # Parsed (not classified) entries are memoized per category so
  # #pending_entries, #dismissed_entries, and #dismissed_entries_for can
  # each read a category's file without re-parsing it more than once.
  # ---------------------------------------------------------------------------

  def parse_file(cat)
    @parsed_files ||= {}
    @parsed_files[cat] ||= begin
      path = File.join(bible_dir, FILE_MAP[cat])
      content = File.read(path, encoding: "UTF-8")
      content.encode!("UTF-8", invalid: :replace, undef: :replace, replace: "")
      @matcher.parse(cat, content)
    rescue Errno::ENOENT, Errno::EACCES
      []
    end
  end

  def dismissed_keys
    @dismissed_keys ||= JSON.parse(@novel.preread_dismissed_keys || "[]")
  rescue JSON::ParserError
    []
  end
end
