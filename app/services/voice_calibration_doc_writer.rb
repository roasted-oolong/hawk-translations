class VoiceCalibrationDocWriter
  RELATIVE_PATH = "bible/voice_calibration.md"

  def initialize(novel)
    @novel = novel
  end

  # Writes (or replaces, if already present) the passage's block in
  # voice_calibration.md so future review runs see it as already covered.
  def upsert(passage)
    return unless path

    existing = File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
    without_old = strip_block(existing, passage.heading)
    updated = without_old.rstrip + "\n\n---\n\n" + format_block(passage) + "\n"
    File.write(path, updated)
  end

  def remove(heading)
    return false unless path && File.exist?(path)

    content = File.read(path, encoding: "UTF-8")
    updated = strip_block(content, heading)
    return false if updated == content

    File.write(path, updated.gsub(/\n{3,}/, "\n\n").rstrip + "\n")
    true
  end

  private

  def path
    root = ENV.fetch("HAWK_PROJECT_ROOT", "")
    return nil if root.blank? || @novel.directory_name.blank?
    File.join(root, @novel.directory_name, RELATIVE_PATH)
  end

  # Removes the "## heading" block through the next "---" divider (or end of
  # file), including a preceding divider if present, so re-upserting the same
  # heading doesn't leave duplicates.
  def strip_block(content, heading)
    pattern = /(?:\n---\n\n)?## #{Regexp.escape(heading.sub(/\A#+\s*/, "").strip)}.*?(?=\n---\n|\z)/m
    content.sub(pattern, "")
  end

  def format_block(passage)
    lines = [ "## #{passage.heading}" ]
    lines << "*#{passage.chapter_ref}*" if passage.chapter_ref.present?
    lines << ""
    lines << passage.quote.to_s.split("\n").map { |l| "> #{l}" }.join("\n")
    lines << ""

    if passage.what_it_demonstrates.present?
      lines << "**What it demonstrates:** #{passage.what_it_demonstrates}"
      lines << ""
    end

    if passage.wrong_version.present?
      lines << "**What the wrong version looks like:** #{passage.wrong_version}"
      lines << ""
    end

    lines << "**The rule it demonstrates:** #{passage.rule}"
    lines.join("\n")
  end
end
