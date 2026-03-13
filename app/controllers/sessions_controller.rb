class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create failure]

  # GET /login
  def new
    redirect_to root_path if authenticated?
  end

  # GET /auth/google_oauth2/callback
  def create
    user = User.from_omniauth(request.env["omniauth.auth"])
    session[:user_id] = user.id
    redirect_to root_path, notice: "Signed in as #{user.name}"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("OmniAuth sign-in failed: #{e.message}")
    redirect_to login_path, alert: "Sign-in failed. Please try again."
  end

  # GET /auth/failure
  def failure
    redirect_to login_path, alert: "Google sign-in was denied or failed. Please try again."
  end

  # DELETE /logout
  def destroy
    session.delete(:user_id)
    @current_user = nil
    redirect_to login_path, notice: "You have been signed out."
  end
end
