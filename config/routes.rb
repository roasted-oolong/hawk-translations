Rails.application.routes.draw do
  # Health check — used by load balancers / uptime monitors
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication
  get  "/login",                        to: "sessions#new",     as: :login
  get  "/auth/google_oauth2/callback",  to: "sessions#create"
  get  "/auth/failure",                 to: "sessions#failure"
  delete "/logout",                     to: "sessions#destroy", as: :logout

  # Root — placeholder dashboard until Milestone 5
  root "dashboard#index"
end
