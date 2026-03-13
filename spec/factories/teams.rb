FactoryBot.define do
  factory :team do
    association :organization
    sequence(:name) { |n| "Team #{n}" }
  end
end
