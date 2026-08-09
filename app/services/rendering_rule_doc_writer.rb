# frozen_string_literal: true

# Formats a resolved set of RenderingRule-like objects (typically
# RenderingRule.effective_for(novel)) into bible/rendering_guide.md — the
# file PromptBuilder actually reads via NOVEL_FILES. Deliberately dumb about
# where the rules came from: the DB is the source of truth, this class only
# knows how to turn a given list of rules into that one file, fully
# rewriting it on every #write rather than patching it in place, so the
# file can never drift from what the DB currently resolves to. Takes a
# plain novel_dir rather than a Novel + ENV["HAWK_PROJECT_ROOT"] lookup —
# resolving that directory is the caller's job, not this class's.
class RenderingRuleDocWriter
  RELATIVE_PATH = "bible/rendering_guide.md"

  def initialize(novel_dir)
    @novel_dir = novel_dir
  end

  # Given no rules, removes the file (if any) rather than leaving an empty
  # guide behind as a spurious "Rendering Guide" reference-material section.
  def write(rules)
    return if @novel_dir.blank?

    if rules.empty?
      File.delete(path) if File.exist?(path)
      return
    end

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, format_guide(rules))
  end

  private

  def path
    File.join(@novel_dir, RELATIVE_PATH)
  end

  def format_guide(rules)
    sections = [ "# Rendering Guide" ] + rules.map { |rule| format_rule(rule) }
    sections.join("\n\n---\n\n") + "\n"
  end

  def format_rule(rule)
    lines = [ "## #{rule.name}", "", rule.guidance.to_s.strip ]
    if rule.example_input.present? || rule.example_output.present?
      lines << ""
      lines << "Example:"
      lines << "> Korean: #{rule.example_input}"  if rule.example_input.present?
      lines << "> English: #{rule.example_output}" if rule.example_output.present?
    end
    lines.join("\n")
  end
end
