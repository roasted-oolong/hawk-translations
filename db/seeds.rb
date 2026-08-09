# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# ---------------------------------------------------------------------------
# Rendering Guide defaults (RenderingRule, novel_id: nil)
#
# American-literary-convention starting points, not mandates — any novel can
# override a given rule_key with its own row (see RenderingRule.effective_for).
# Only find_or_create_by! (attributes set on creation only, via the block
# form) so re-running seeds never clobbers content someone has since edited
# by hand.
# ---------------------------------------------------------------------------
[
  {
    rule_key: "dialogue",
    name: "Spoken dialogue",
    guidance: "Use double quotation marks for spoken dialogue. Keep the punctuation inside the closing mark, and let interruptions follow the rhythm of the Korean source rather than adding explanatory tags.",
    example_input: "“돌아가야 해.” 그가 말했다.",
    example_output: "“I should go back,” he said.",
    position: 0
  },
  {
    rule_key: "thoughts",
    name: "Internal thoughts",
    guidance: "Thoughts sit in the same typographic world as the prose. Use single quotation marks to signal a distinct interior voice; do not italicize thoughts.",
    example_input: "돌아가야 한다고 생각했다.",
    example_output: "'I should turn back.'",
    position: 1
  },
  {
    rule_key: "titles",
    name: "Book / show titles",
    guidance: "Keep the source title's angle brackets and translate only the title text where an established English rendering does not exist. Do not replace the brackets with italics.",
    example_input: "〈푸른 시간〉을 다시 봤다.",
    example_output: "He watched 〈The Blue Hour〉 again.",
    position: 2
  },
  {
    rule_key: "onomatopoeia",
    name: "Onomatopoeia",
    guidance: "Fold sound words into the action wherever possible. Keep a standalone sound only when its visual or rhythmic presence is part of the storytelling.",
    example_input: "쿵! 문이 닫혔다.",
    example_output: "The door slammed shut.",
    position: 3
  }
].each do |attrs|
  RenderingRule.find_or_create_by!(rule_key: attrs[:rule_key], novel_id: nil) do |rule|
    rule.name = attrs[:name]
    rule.guidance = attrs[:guidance]
    rule.example_input = attrs[:example_input]
    rule.example_output = attrs[:example_output]
    rule.position = attrs[:position]
  end
end
