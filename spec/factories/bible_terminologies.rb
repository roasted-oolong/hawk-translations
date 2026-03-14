FactoryBot.define do
  factory :bible_terminology do
    association :novel
    sequence(:term) { |n| "Term #{n}" }
    korean_term              { nil }
    definition               { nil }
    usage_notes              { nil }
    first_appearance_chapter { nil }
    notes                    { nil }
  end
end
