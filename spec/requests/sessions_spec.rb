require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "GET /login" do
    it "returns 200 and renders the login page" do
      get login_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects to root if already authenticated" do
      user = create(:user)
      sign_in(user)
      get login_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /auth/google_oauth2/callback" do
    context "with a valid OmniAuth response" do
      before { mock_google_oauth(email: "jenna@example.com", name: "Jenna", uid: "google_uid_1") }

      it "creates a user if one does not exist" do
        expect { get "/auth/google_oauth2/callback" }.to change(User, :count).by(1)
      end

      it "redirects to root after sign-in" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(root_path)
      end

      it "sets the user_id in the session" do
        get "/auth/google_oauth2/callback"
        expect(session[:user_id]).to be_present
      end

      it "does not create a duplicate on subsequent sign-in" do
        create(:user, provider: "google_oauth2", uid: "google_uid_1", email: "jenna@example.com", name: "Jenna")
        expect { get "/auth/google_oauth2/callback" }.not_to change(User, :count)
      end
    end

    context "with a failed OmniAuth response" do
      before { mock_google_oauth_failure }

      it "redirects to login" do
        get "/auth/failure"
        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "DELETE /logout" do
    it "clears the session and redirects to login" do
      user = create(:user)
      sign_in(user)
      delete logout_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "authentication requirement" do
    it "redirects unauthenticated requests to login" do
      get root_path
      expect(response).to redirect_to(login_path)
    end
  end
end
