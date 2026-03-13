FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Test User" }
    provider { "google_oauth2" }
    sequence(:uid) { |n| "google_uid_#{n}" }
    platform_admin { false }
  end
end
