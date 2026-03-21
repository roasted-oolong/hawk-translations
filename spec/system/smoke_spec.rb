require "rails_helper"

# Smoke test — M13 system spec driver verification.
#
# Confirms:
#   1. The app boots and serves a response.
#   2. The login page renders without a JS-capable driver error.
#   3. The authenticated OAuth flow completes (Capybara + Cuprite).
#
# This spec is intentionally minimal — it is infrastructure verification,
# not feature coverage. Feature system specs begin at M14.

RSpec.describe "Smoke test", type: :system do
  it "renders the login page" do
    visit login_path
    expect(page).to have_current_path(login_path)
    expect(page).to have_selector("body")
  end

  it "redirects unauthenticated requests to login" do
    visit root_path
    expect(page).to have_current_path(login_path)
  end

  it "completes the OAuth sign-in flow and reaches the authenticated app" do
    mock_google_oauth(
      email: "smoke@example.com",
      name:  "Smoke User",
      uid:   "smoke-uid-001"
    )

    visit "/auth/google_oauth2/callback"

    # After successful OAuth the user is redirected away from login.
    expect(page).not_to have_current_path(login_path)
  end
end
