# ---------------------------------------------------------------------------
# Pipeline::Ruby::PrereadRunner::ChapterDiscovery
#
# Ruby port of the chapter-discovery predicates from src/novel_resolver.py
# (find_all_korean_chapters, find_untranslated_chapters,
# find_translated_chapter_numbers, extract_chapter_number) plus
# src/preread/chapter_resolver.py's _filter_and_warn (here:
# .filter_to_available). This is real, still-exercised safety-net behavior —
# not CLI-selection-parsing convenience — so it's ported, unlike R4/R5's
# chapter-selection parsing, which Rails already makes unnecessary.
#
# Pure functions only: given a chapters_dir path (or a requested/available
# pair), return chapter numbers. No file writes, no logging — callers decide
# how to surface FilterResult#skipped.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class PrereadRunner
      module ChapterDiscovery
        FilterResult = Struct.new(:selected, :skipped)

        def self.extract_chapter_number(filename)
          match = filename.match(/(\d+)/)
          match && match[1].to_i
        end

        # Chapter numbers with a translated .txt file, excluding korean source
        # files and reference translations ("another translation" in the name).
        def self.find_translated_chapter_numbers(chapters_dir)
          each_file(chapters_dir).each_with_object(Set.new) do |name, translated|
            next unless File.extname(name).downcase == ".txt"
            next if name.downcase.include?("korean")
            next if name.downcase.include?("another translation")

            n = extract_chapter_number(name)
            translated << n if n
          end
        end

        # Sorted list of all chapter numbers with a *_korean source file.
        def self.find_all_korean_chapters(chapters_dir)
          each_file(chapters_dir).filter_map { |name| extract_chapter_number(name) if name.downcase.include?("korean") }.sort
        end

        # Chapter numbers with a korean source file but no translated .txt yet.
        def self.find_untranslated_chapters(chapters_dir)
          translated = find_translated_chapter_numbers(chapters_dir)
          find_all_korean_chapters(chapters_dir).reject { |n| translated.include?(n) }
        end

        # Filter requested chapter numbers down to the available set, sorted
        # and deduped; skipped numbers are reported for the caller to log.
        def self.filter_to_available(requested, available)
          available_set = available.to_set
          selected = requested.select { |n| available_set.include?(n) }.uniq.sort
          skipped  = requested.reject { |n| available_set.include?(n) }.uniq
          FilterResult.new(selected, skipped)
        end

        def self.each_file(chapters_dir)
          Dir.children(chapters_dir).select { |name| File.file?(File.join(chapters_dir, name)) }
        end
        private_class_method :each_file
      end
    end
  end
end
