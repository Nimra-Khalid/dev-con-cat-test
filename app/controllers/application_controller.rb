class ApplicationController < ActionController::Base
  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  def authenticate_user!
    return if current_user

    render json: {
      error: "Authentication required"
    }, status: :unauthorized
  end

  def accessible_leads
    if current_user.super_admin?
      Lead.all
    else
      Lead
        .joins(pixel_session: :pixel)
        .where(pixels: { account_id: current_user.account_id })
    end
  end
end