FactoryBot.define do
  factory :bible_location do
    association :novel
    sequence(:name) { |n| "Location #{n}" }
    korean_name              { nil }
    location_type            { nil }
    description              { nil }
    significance             { nil }
    first_appearance_chapter { nil }
    notes                    { nil }
  end
end
