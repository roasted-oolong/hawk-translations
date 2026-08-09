FactoryBot.define do
  factory :bible_cultural_phrase do
    association :novel
    sequence(:korean_phrase)  { |n| "구절 #{n}" }
    literal_translation       { nil }
    intended_meaning          { nil }
    context                   { nil }
    translation_examples      { [] }
    first_appearance_chapter  { nil }
    notes                     { nil }
  end
end
