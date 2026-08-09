FactoryBot.define do
  factory :rendering_rule do
    novel { nil }
    sequence(:rule_key) { |n| "rule-#{n}" }
    sequence(:name)     { |n| "Rendering rule #{n}" }
    guidance             { "State the convention as a checkable rule." }
    example_input        { "Example Korean source line." }
    example_output       { "Example English rendering." }
    sequence(:position)

    trait :override do
      association :novel
    end
  end
end
