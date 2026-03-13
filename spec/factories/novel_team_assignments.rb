FactoryBot.define do
  factory :novel_team_assignment do
    association :novel
    association :team
    permission_level { "translator" }
  end
end
