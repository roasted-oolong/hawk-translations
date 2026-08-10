FactoryBot.define do
  factory :bible_entry_proposal do
    association :novel
    chapter { association(:chapter, novel: novel) }
    entry_type          { "character" }
    existing_record_id  { nil }
    sequence(:korean_key) { |n| "korean-key-#{n}" }
    fields { { "name" => "Test Name" } }
    status { "pending" }
  end
end
