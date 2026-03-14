FactoryBot.define do
  factory :chapter do
    association :novel
    sequence(:number) { |n| n }
    title  { nil }
    status { "untranslated" }
  end
end
