FactoryBot.define do
  factory :voice_calibration_passage do
    association :novel
    sequence(:heading) { |n| "Passage #{n} — Example pattern" }
    chapter_ref           { "Chapter 1" }
    quote                 { "An example quoted line." }
    what_it_demonstrates  { nil }
    wrong_version         { nil }
    rule                  { "State the rule as a principle." }
    sequence(:position)
  end
end
