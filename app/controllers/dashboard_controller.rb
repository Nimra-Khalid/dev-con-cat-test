class DashboardController < ApplicationController
  before_action :require_browser_login!, except: [:login]

  def login
    redirect_to "/crm" if current_user
  end

  def index
    redirect_to "/crm"
  end

  def crm
    @current_user = current_user
  end

  def lead
    @current_user = current_user

    @lead = accessible_leads.find_by!(
      external_id: params[:id]
    )
  end

  def pixels
  @current_user = current_user

  unless current_user.account_admin? || current_user.super_admin?
    redirect_to "/crm"
  end
  end

  private

  def require_browser_login!
    redirect_to "/login-page" unless current_user
  end
end