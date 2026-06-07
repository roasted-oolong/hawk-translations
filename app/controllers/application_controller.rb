class ApplicationController < ActionController::Base
  # Register app/views/components/ as an additional view path so component
  # partials can be rendered as `render "component_name"` from controllers.
  # Note: when rendering from within another partial, use the explicit path:
  # `render "components/component_name"` to avoid lookup ambiguity.
  prepend_view_path Rails.root.join("app/views/components")

  helper_method :current_user

  private

  def current_user
    @current_user ||= User.first
  end
end
