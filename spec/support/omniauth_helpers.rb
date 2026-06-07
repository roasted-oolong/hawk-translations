module OmniauthHelpers
  def mock_google_oauth(email:, name:, uid:)
    return unless defined?(OmniAuth)

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name }
    )
  end

  def mock_google_oauth_failure
    return unless defined?(OmniAuth)

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
  end

  def sign_in(user)
    mock_google_oauth(email: user.email, name: user.name, uid: user.uid)
    get "/auth/google_oauth2/callback"
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers, type: :request
  config.include OmniauthHelpers, type: :system

  config.before(:each, type: :request) do
    OmniAuth.config.test_mode = true if defined?(OmniAuth)
  end

  config.after(:each) do
    next unless defined?(OmniAuth)

    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:google_oauth2)
  end
end
