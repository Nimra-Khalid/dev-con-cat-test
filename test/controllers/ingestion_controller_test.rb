require "test_helper"

class IngestionControllerTest < ActionDispatch::IntegrationTest
  def setup
    @account = Account.create!(
      external_id: "acct_ingestion_test",
      company_name: "Ingestion Test Account",
      plan: "growth",
      monthly_credit_allowance: 100,
      credits_used_this_cycle: 0,
      status: "active",
      enabled_modules: [
        "anura",
        "trustedform",
        "dnc"
      ]
    )

    @pixel = @account.pixels.create!(
      public_id: "px_ingestion_test",
      name: "Ingestion Test Pixel",
      allowed_pages: [
        "https://example.com"
      ],
      enabled_modules: [
        "anura",
        "trustedform",
        "dnc"
      ],
      active: true
    )
  end

  test "visit creates a pixel session" do
    post "/visit",
         params: {
           pixel_id: @pixel.public_id,
           session_id: "session_ingestion_1",
           page_url: "https://example.com/landing",
           referrer: "https://google.com",
           user_agent: "Test Browser",
           started_at: Time.current.iso8601
         },
         as: :json

    assert_response :created

    session =
      PixelSession.find_by!(
        session_id: "session_ingestion_1"
      )

    assert_equal @pixel.id, session.pixel_id
    assert_equal(
      "https://example.com/landing",
      session.page_url
    )
  end

  test "visit rejects invalid landing page" do
    post "/visit",
         params: {
           pixel_id: @pixel.public_id,
           session_id: "session_bad_page",
           page_url: "https://evil.example.net",
           started_at: Time.current.iso8601
         },
         as: :json

    assert_response :forbidden
  end

  test "lead submission creates lead and returns verdict" do
    session =
      @pixel.pixel_sessions.create!(
        session_id: "session_ingestion_2",
        page_url: "https://example.com/landing",
        started_at: Time.current
      )

    post "/leads",
         params: {
           pixel_id: @pixel.public_id,
           session_id: session.session_id,

           # Using an existing fixture lead ID
           # lets the VerificationRunner find
           # matching mock provider responses.
           lead_id: "L-1001",

           submitted_at: Time.current.iso8601,
           form_dwell_ms: 2500,

           fields: {
             first_name: "Jane",
             last_name: "Doe",
             email: "jane@example.com",
             phone: "5551234567"
           }
         },
         as: :json

    assert_response :created

    body = JSON.parse(response.body)

    assert_equal "L-1001", body["lead_id"]
    assert_equal "ACCEPT", body["verdict"]

    lead =
      Lead.find_by!(
        external_id: "L-1001"
      )

    assert_equal session.id, lead.pixel_session_id
    assert_equal "jane@example.com", lead.email

    assert_equal(
      1,
      lead.verification_runs.count
    )
  end
end