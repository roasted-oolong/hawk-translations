FactoryBot.define do
  factory :bible_story_entry do
    association :novel
    sequence(:title) { |n| "Story Entry #{n}" }
    category                 { "main_plot" }
    content                  { nil }
    first_appearance_chapter { nil }
    notes                    { nil }
  end
end
