FactoryBot.define do
  factory :bible_cultural_phrase do
    association :novel
    sequence(:phrase) { |n| "Phrase #{n}" }
    korean_phrase            { nil }
    literal_translation      { nil }
    intended_meaning         { nil }
    context                  { nil }
    established_translation  { nil }
    first_appearance_chapter { nil }
    notes                    { nil }
  end
end
