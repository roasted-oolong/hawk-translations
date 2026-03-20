FactoryBot.define do
  factory :translation_job do
    association :novel
    association :user

    job_type      { "preread" }
    status        { "queued" }
    chapter_start { 1 }
    chapter_end   { 5 }
    result_payload { nil }
    solid_queue_job_id { nil }

    trait :bible_build do
      job_type      { "bible_build" }
      chapter_start { nil }
      chapter_end   { nil }
    end

    trait :post_translation_review do
      job_type      { "post_translation_review" }
      chapter_start { 1 }
      chapter_end   { 1 }
    end

    trait :queued do
      status { "queued" }
    end

    trait :running do
      status { "running" }
    end

    trait :completed do
      status        { "completed" }
      result_payload { "Job completed successfully." }
    end

    trait :failed do
      status        { "failed" }
      result_payload { "Error: something went wrong." }
    end
  end
end
