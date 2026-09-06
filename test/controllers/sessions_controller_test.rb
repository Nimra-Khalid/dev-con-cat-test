require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = Account.create!(
      external_id: "acct_auth_test",
      company_name: "Auth Test Account",
      plan: "growth",
      monthly_credit_allowance: 1_000,
      credits_used_this_cycle: 0,
      status: "active",
      avg_daily_burn: 10,
      enabled_modules: []
    )

    @user = User.create!(
      external_id: "usr_auth_test",
      name: "Auth Test User",
      email: "auth-test@example.com",
      role: "account_admin",
      account: @account,
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "logs in with valid credentials" do
    post "/login", params: {
      email: @user.email,
      password: "password123"
    }, as: :json

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal @user.email, body["user"]["email"]
    assert_equal "account_admin", body["user"]["role"]
  end

  test "rejects invalid password" do
    post "/login", params: {
      email: @user.email,
      password: "wrong-password"
    }, as: :json

    assert_response :unauthorized

    body = JSON.parse(response.body)

    assert_equal "Invalid email or password", body["error"]
  end

  test "returns current user after login" do
    post "/login", params: {
      email: @user.email,
      password: "password123"
    }, as: :json

    get "/me", as: :json

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal @user.id, body["user"]["id"]
    assert_equal @account.id, body["user"]["account_id"]
  end

  test "returns unauthorized when not logged in" do
    get "/me", as: :json

    assert_response :unauthorized
  end

  test "logout clears the session" do
    post "/login", params: {
      email: @user.email,
      password: "password123"
    }, as: :json

    delete "/logout", as: :json

    assert_response :success

    get "/me", as: :json

    assert_response :unauthorized
  end
end