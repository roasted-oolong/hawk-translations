FactoryBot.define do
  factory :series do
    association :organization
    sequence(:name) { |n| "Series #{n}" }
  end
end
