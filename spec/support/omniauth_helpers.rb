module OmniauthHelpers
  def mock_google_oauth(email:, name:, uid:)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name }
    )
  end

  def mock_google_oauth_failure
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
  end

  # Signs in a user by driving the real OAuth callback with a mocked auth hash.
  # Sets session[:user_id] via the actual SessionsController#create code path.
  # Use this in request specs instead of forging cookies.
  def sign_in(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    get "/auth/google_oauth2/callback"
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers, type: :request
  config.include OmniauthHelpers, type: :system

  config.before(:each, type: :request) do
    OmniAuth.config.test_mode = true
  end

  config.after(:each) do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:google_oauth2)
  end
end
