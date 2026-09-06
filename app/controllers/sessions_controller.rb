class SessionsController < ApplicationController
  skip_forgery_protection only: [:create, :destroy]

  def create
    user = User.find_by(
      email: params[:email].to_s.downcase.strip
    )

    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id

      render json: {
        user: {
          id: user.id,
          external_id: user.external_id,
          name: user.name,
          email: user.email,
          role: user.role,
          account_id: user.account_id
        }
      }, status: :ok
    else
      render json: {
        error: "Invalid email or password"
      }, status: :unauthorized
    end
  end

  def destroy
    reset_session

    render json: {
      message: "Logged out successfully"
    }, status: :ok
  end

  def show
    if current_user
      render json: {
        user: {
          id: current_user.id,
          external_id: current_user.external_id,
          name: current_user.name,
          email: current_user.email,
          role: current_user.role,
          account_id: current_user.account_id
        }
      }, status: :ok
    else
      render json: {
        error: "Not authenticated"
      }, status: :unauthorized
    end
  end
end