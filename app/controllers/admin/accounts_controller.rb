module Admin
  class AccountsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_super_admin!

    def index
      accounts = Account.order(:company_name)

      render json: {
        results: accounts.map do |account|
          serialize_account(account)
        end
      }
    end

    private

    def authorize_super_admin!
      return if current_user.super_admin?

      render json: {
        error: "Super admin access required"
      }, status: :forbidden
    end

    def serialize_account(account)
      remaining = account.credits_remaining

      estimated_days_remaining =
        if account.avg_daily_burn.positive?
          (remaining.to_f / account.avg_daily_burn).round(1)
        end

      nearly_out =
        remaining <= [account.avg_daily_burn * 3, 100].max

      {
        external_id: account.external_id,
        company_name: account.company_name,
        plan: account.plan,
        status: account.status,

        credits: {
          monthly_allowance:
            account.monthly_credit_allowance,

          used:
            account.credits_used_this_cycle,

          remaining: remaining
        },

        avg_daily_burn:
          account.avg_daily_burn,

        estimated_days_remaining:
          estimated_days_remaining,

        nearly_out:
          nearly_out,

        cycle_start:
          account.cycle_start,

        cycle_end:
          account.cycle_end,

        enabled_modules:
          account.enabled_modules
      }
    end
  end
end