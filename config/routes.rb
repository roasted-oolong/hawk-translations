Rails.application.routes.draw do
  # Health check — used by load balancers / uptime monitors
  get "up" => "rails/health#show", as: :rails_health_check

  # Novels + nested resources
  resources :novels, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    member do
      # Cover art — purge the attachment for a novel
      delete "cover_art", action: :destroy_cover_art, as: :cover_art
    end

    # Must be declared before resources :chapters so Rails matches this
    # before the parameterized GET /chapters/:id route.
    get "chapters/review", to: "chapter_review#tab",  as: :chapter_review_tab

    resources :chapters, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      member do
        get   :download_korean_source
        get   :download_translated_output
        patch :approve
      end
      collection do
        delete :bulk_destroy
        post   :bulk_download
        patch  :bulk_update
        patch  :approve_all
      end
    end

    # Bible entry tables — one nested resource block per category
    resources :bible_characters,       only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :bible_locations,        only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :bible_terminologies,    only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :bible_cultural_phrases, only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :bible_story_entries,    only: [ :index, :show, :new, :create, :edit, :update, :destroy ]

    # Translation jobs — trigger, list, show output, cancel
    resources :translation_jobs, only: [ :index, :show, :create, :destroy ] do
      collection do
        delete :bulk_cancel
      end
    end

    # Bible landing page — search + category overview (Milestone 17)
    # GET /novels/:novel_id/bible
    # as: :bible generates novel_bible_path (Rails prepends :novel_ from the resources block)
    get "bible", to: "bible#show", as: :bible

    # Bible search — API-first JSON endpoint (Milestone 12)
    # GET /novels/:novel_id/bible/search?q=...
    # as: :bible_search generates novel_bible_search_path (Rails prepends :novel_ from the resources block)
    get "bible/search", to: "bible_search#show", as: :bible_search

    # Full-page chapter review slideshow
    # GET  /novels/:novel_id/chapter_review              → novel_chapter_review_path
    # PATCH /novels/:novel_id/chapter_review/chapters/:id/text → save edited text
    get   "chapter_review",                         to: "chapter_review#show",        as: :chapter_review
    patch "chapter_review/chapters/:id/text",       to: "chapter_review#update_text", as: :update_chapter_review_text

    # Preread results review + bible import
    # GET  /novels/:novel_id/preread_review  → novel_preread_review_path
    # POST /novels/:novel_id/bible_import    → novel_bible_import_path
    get  "preread_review", to: "preread_review#show", as: :preread_review
    post "bible_import",   to: "bible_import#create", as: :bible_import

    # Voice calibration tab (Turbo Frame) + full-page review
    # GET   /novels/:novel_id/voice_calibration               → novel_voice_calibration_tab_path
    # GET   /novels/:novel_id/voice_calibration/review        → novel_voice_calibration_review_path
    # PATCH /novels/:novel_id/voice_calibration/review/cards/:card_id → novel_voice_calibration_review_card_path
    # POST  /novels/:novel_id/voice_calibration/review/commit → novel_voice_calibration_review_commit_path
    get   "voice_calibration",                       to: "voice_calibration#tab",           as: :voice_calibration_tab
    get   "voice_calibration/review",                to: "voice_calibration_review#show",   as: :voice_calibration_review
    patch "voice_calibration/review/cards/:card_id", to: "voice_calibration_review#update", as: :voice_calibration_review_card
    post  "voice_calibration/review/commit",         to: "voice_calibration_review#commit", as: :voice_calibration_review_commit
  end

  # Top-level jobs index — cross-novel view
  get "translation_jobs", to: "jobs#index", as: :translation_jobs

  # Root
  root "dashboard#index"
end
