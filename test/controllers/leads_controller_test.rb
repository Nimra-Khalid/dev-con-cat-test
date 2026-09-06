require "test_helper"

class LeadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @solar = Account.create!(
      external_id: "acct_solar_test",
      company_name: "Solar Test",
      plan: "growth",
      monthly_credit_allowance: 10_000,
      credits_used_this_cycle: 0,
      status: "active",
      avg_daily_burn: 100,
      enabled_modules: []
    )

    @medicare = Account.create!(
      external_id: "acct_medicare_test",
      company_name: "Medicare Test",
      plan: "enterprise",
      monthly_credit_allowance: 10_000,
      credits_used_this_cycle: 0,
      status: "active",
      avg_daily_burn: 100,
      enabled_modules: []
    )

    @solar_user = User.create!(
      external_id: "usr_solar_test",
      name: "Solar Admin",
      email: "solar-test@example.com",
      role: "account_admin",
      account: @solar,
      password: "password123",
      password_confirmation: "password123"
    )

    @super_admin = User.create!(
      external_id: "usr_super_test",
      name: "Super Admin",
      email: "super-test@example.com",
      role: "super_admin",
      account: nil,
      password: "password123",
      password_confirmation: "password123"
    )

    @solar_pixel = Pixel.create!(
      public_id: "px_solar_test",
      account: @solar,
      name: "Solar Pixel",
      allowed_pages: [],
      enabled_modules: [],
      active: true
    )

    @medicare_pixel = Pixel.create!(
      public_id: "px_medicare_test",
      account: @medicare,
      name: "Medicare Pixel",
      allowed_pages: [],
      enabled_modules: [],
      active: true
    )

    solar_session = PixelSession.create!(
      session_id: "session_solar_test",
      pixel: @solar_pixel,
      page_url: "https://solar.test",
      started_at: Time.current
    )

    medicare_session = PixelSession.create!(
      session_id: "session_medicare_test",
      pixel: @medicare_pixel,
      page_url: "https://medicare.test",
      started_at: Time.current
    )

    @solar_lead = Lead.create!(
  external_id: "lead_solar_test",
  pixel_session: solar_session,
  first_name: "Solar",
  last_name: "Lead",
  email: "solar-lead@example.com",
  phone: "1111111111",
  landing_page_url: "https://solar.test/landing",
  submitted_at: Time.current
)

    @medicare_lead = Lead.create!(
  external_id: "lead_medicare_test",
  pixel_session: medicare_session,
  first_name: "Medicare",
  last_name: "Lead",
  email: "medicare-lead@example.com",
  phone: "2222222222",
  landing_page_url: "https://medicare.test/landing",
  submitted_at: Time.current
)
  end

  test "requires authentication" do
    get "/crm/leads"

    assert_response :unauthorized
  end

  test "account user only sees leads from own account" do
    login(@solar_user)

    get "/crm/leads"

    assert_response :success

    body = JSON.parse(response.body)
ids = body["results"].map { |lead| lead["id"] }

    assert_includes ids, @solar_lead.external_id
    assert_not_includes ids, @medicare_lead.external_id
  end

  test "account user cannot access another account lead directly" do
    login(@solar_user)

    get "/crm/leads/#{@medicare_lead.external_id}"

    assert_response :not_found
  end

  test "super admin can see leads across accounts" do
    login(@super_admin)

    get "/crm/leads"

    assert_response :success

    body = JSON.parse(response.body)
ids = body["results"].map { |lead| lead["id"] }

    assert_includes ids, @solar_lead.external_id
    assert_includes ids, @medicare_lead.external_id
  end

  private

  def login(user)
    post "/login",
      params: {
        email: user.email,
        password: "password123"
      },
      as: :json

    assert_response :success
  end
end