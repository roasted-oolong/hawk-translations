FactoryBot.define do
  factory :membership do
    association :user
    association :team
    role { "team_member" }
  end
end
