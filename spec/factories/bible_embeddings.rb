# frozen_string_literal: true

FactoryBot.define do
  factory :bible_embedding do
    # Polymorphic association — default to BibleCharacter for convenience.
    # Override in tests that need other embeddable types:
    #   create(:bible_embedding, embeddable: my_location, novel: my_novel)
    association :embeddable, factory: :bible_character

    # novel and organization must be consistent with the embeddable's novel.
    # The factory sets novel from the embeddable's novel; callers must pass
    # novel explicitly when creating the embeddable separately:
    #   char  = create(:bible_character, novel: novel)
    #   emb   = create(:bible_embedding, embeddable: char, novel: novel)
    novel { embeddable.novel }
    organization { novel&.organization }

    sequence(:content_hash) { |n| "hash_#{n}" }

    # embedding and search_text are nullable — left nil by default.
    # Tests that exercise vector search should set embedding explicitly.
    embedding   { nil }
    search_text { nil }
  end
end
