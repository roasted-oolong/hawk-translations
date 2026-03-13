Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    Rails.application.credentials.dig(:google, :client_id),
    Rails.application.credentials.dig(:google, :client_secret)
end

# OmniAuth 2.x requires POST for the initiation request by default.
# omniauth-rails_csrf_protection handles the CSRF token on that POST.
# The callback is a GET (driven by Google redirect), which is correct.
OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.silence_get_warning = true
