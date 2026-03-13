FactoryBot.define do
  factory :novel do
    association :organization
    series     { nil }
    poc_user   { nil }
    sequence(:title) { |n| "Novel #{n}" }
    korean_title { nil }
    genre        { nil }
    visibility   { "discoverable" }
  end
end
