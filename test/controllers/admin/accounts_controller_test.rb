require "test_helper"

class Admin::AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = Account.create!(
      external_id: "acct_admin_dashboard",
      company_name: "Admin Dashboard Co",
      plan: "growth",
      monthly_credit_allowance: 10_000,
      credits_used_this_cycle: 8_000,
      avg_daily_burn: 800,
      status: "active",
      enabled_modules: [
        "anura",
        "trustedform"
      ]
    )

    @super_admin = User.create!(
      external_id: "usr_super_dashboard",
      name: "Super Admin",
      email: "super-dashboard@example.com",
      role: "super_admin",
      account: nil,
      password: "password123",
      password_confirmation: "password123"
    )

    @account_admin = User.create!(
      external_id: "usr_account_dashboard",
      name: "Account Admin",
      email: "account-dashboard@example.com",
      role: "account_admin",
      account: @account,
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "authentication is required" do
    get "/admin/accounts"

    assert_response :unauthorized
  end

  test "account admin cannot access all accounts" do
    login_as(@account_admin)

    get "/admin/accounts"

    assert_response :forbidden
  end

  test "super admin can view all accounts" do
    login_as(@super_admin)

    get "/admin/accounts"

    assert_response :success

    body = JSON.parse(response.body)

    ids = body["results"].map do |account|
      account["external_id"]
    end

    assert_includes ids, @account.external_id
  end

  test "response includes credit and burn information" do
    login_as(@super_admin)

    get "/admin/accounts"

    body = JSON.parse(response.body)

    account = body["results"].find do |item|
      item["external_id"] == @account.external_id
    end

    assert_equal 10_000,
                 account["credits"]["monthly_allowance"]

    assert_equal 8_000,
                 account["credits"]["used"]

    assert_equal 2_000,
                 account["credits"]["remaining"]

    assert_equal 800,
                 account["avg_daily_burn"]

    assert_equal 2.5,
                 account["estimated_days_remaining"]

    assert_equal true,
                 account["nearly_out"]
  end

  private

  def login_as(user)
    post "/login",
         params: {
           email: user.email,
           password: "password123"
         },
         as: :json

    assert_response :success
  end
end