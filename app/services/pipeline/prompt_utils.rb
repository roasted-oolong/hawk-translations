# ---------------------------------------------------------------------------
# Pipeline::PromptUtils
#
# Ruby port of src/prompt_utils.py — shared utilities for assembling prompts
# from bible file content. Used by both R4's translation prompt builder and
# R6's preread prompt builder, so empty-detection/section-formatting only
# needs to change in one place.
# ---------------------------------------------------------------------------
module Pipeline
  module PromptUtils
    # Strings that indicate a bible file contains only its blank template.
    # Sections matching any of these are omitted from prompts.
    EMPTY_MARKERS = [
      "[Character Name",
      "[Term —",
      "[Phrase —",
      "[Location Name",
      "Current summary: \n- Key turning points:"
    ].freeze

    def self.empty?(content)
      return true if content.nil? || content.strip.empty?
      EMPTY_MARKERS.any? { |marker| content.include?(marker) }
    end

    def self.section(heading, content)
      return "" if empty?(content)
      "## #{heading}\n\n#{content.strip}\n"
    end
  end
end
