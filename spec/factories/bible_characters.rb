FactoryBot.define do
  factory :bible_character do
    association :novel
    sequence(:name) { |n| "Character #{n}" }
    korean_name              { nil }
    aliases                  { nil }
    role                     { nil }
    significance             { nil }
    physical_description     { nil }
    speech_pattern           { nil }
    honorifics_used_toward   { nil }
    honorifics_they_use      { nil }
    relationships            { nil }
    first_appearance_chapter { nil }
    notes                    { nil }
  end
end
