Rails.application.routes.draw do
  # Health check — used by load balancers / uptime monitors
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication
  get  "/login",                        to: "sessions#new",     as: :login
  get  "/auth/google_oauth2/callback",  to: "sessions#create"
  get  "/auth/failure",                 to: "sessions#failure"
  delete "/logout",                     to: "sessions#destroy", as: :logout

  # Novels + nested resources
  resources :novels, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    resources :chapters, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      member do
        get :download_korean_source
        get :download_translated_output
      end
    end

    # Bible entry tables — one nested resource block per category
    resources :bible_characters,     only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :bible_locations,      only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :bible_terminologies,  only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :bible_cultural_phrases, only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
    resources :bible_story_entries,  only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
  end

  # Root
  root "dashboard#index"
end
