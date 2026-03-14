Rails.application.routes.draw do
  # Health check — used by load balancers / uptime monitors
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication
  get  "/login",                        to: "sessions#new",     as: :login
  get  "/auth/google_oauth2/callback",  to: "sessions#create"
  get  "/auth/failure",                 to: "sessions#failure"
  delete "/logout",                     to: "sessions#destroy", as: :logout

  # Novels + nested chapters
  resources :novels, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    resources :chapters, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      member do
        get  :download_korean_source
        get  :download_translated_output
      end
    end
  end

  # Root
  root "dashboard#index"
end
