require "test_helper"

class IngestionControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
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

test "lead submission creates lead and queues verification" do
  session =
    @pixel.pixel_sessions.create!(
      session_id: "session_ingestion_2",
      page_url: "https://example.com/landing",
      started_at: Time.current
    )

  perform_enqueued_jobs do
    post "/leads",
         params: {
           pixel_id: @pixel.public_id,
           session_id: session.session_id,
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
  end

  assert_response :accepted

  body = JSON.parse(response.body)

  assert_equal "L-1001", body["lead_id"]

  assert_equal(
    "verification_queued",
    body["status"]
  )

  lead =
    Lead.find_by!(
      external_id: "L-1001"
    )

  assert_equal(
    session.id,
    lead.pixel_session_id
  )

  assert_equal(
    "jane@example.com",
    lead.email
  )

  assert_equal(
    1,
    lead.verification_runs.count
  )

  assert_equal(
    "ACCEPT",
    lead.verification_runs.last
      .verdict
      .decision
  )
end

  test "activity endpoint returns verification events" do
  session =
    @pixel.pixel_sessions.create!(
      session_id: "session_activity_test",
      page_url: "https://example.com/landing",
      started_at: Time.current
    )

  lead =
    session.create_lead!(
      external_id: "L-1001",
      first_name: "Jane",
      last_name: "Doe",
      email: "jane@example.com",
      phone: "5551234567",
      landing_page_url: session.page_url,
      submitted_at: Time.current
    )

  VerificationRunner.new(lead).call

 get "/leads/#{lead.external_id}/activity",
    params: {
      session_id: session.session_id
    },
    as: :json

  assert_response :success

  body = JSON.parse(response.body)

  assert_equal lead.external_id, body["lead_id"]

  event_types =
    body["events"].map do |event|
      event["event_type"]
    end

  assert_includes(
    event_types,
    "verification_started"
  )

  assert_includes(
    event_types,
    "layer_result"
  )

  assert_includes(
    event_types,
    "final_verdict"
  )
  end

  test "activity endpoint supports after_id polling" do
  session =
    @pixel.pixel_sessions.create!(
      session_id: "session_polling_test",
      page_url: "https://example.com/landing",
      started_at: Time.current
    )

  lead =
    session.create_lead!(
      external_id: "L-1002",
      first_name: "John",
      last_name: "Doe",
      email: "john@example.com",
      phone: "5552223333",
      landing_page_url: session.page_url,
      submitted_at: Time.current
    )

  first_event =
    lead.activity_events.create!(
      event_type: "info",
      payload: {
        message: "First event"
      }
    )

  second_event =
    lead.activity_events.create!(
      event_type: "info",
      payload: {
        message: "Second event"
      }
    )

  get "/leads/#{lead.external_id}/activity",
      params: {
  session_id: session.session_id,
  after_id: first_event.id
},
      as: :json

  assert_response :success

  body = JSON.parse(response.body)

  assert_equal 1, body["events"].length

  assert_equal(
    second_event.id,
    body["events"].first["id"]
  )

  assert_equal(
    "Second event",
    body["events"].first
      .dig("payload", "message")
  )
  end

  test "visit rejects disallowed landing page" do
  post "/visit",
    params: {
      pixel_id: @pixel.public_id,
      session_id: "blocked-session",
      page_url: "https://evil.example.com/form"
    },
    as: :json

  assert_response :forbidden

  body = JSON.parse(response.body)

  assert_equal(
    "Landing page is not allowed for this pixel",
    body["error"]
  )
 end

 test "visit allows configured page with query parameters" do
  @pixel.update!(
    allowed_pages: [
      "https://example.com/form"
    ]
  )

  post "/visit",
    params: {
      pixel_id: @pixel.public_id,
      session_id: "query-session",
      page_url:
        "https://example.com/form?utm_source=google"
    },
    as: :json

  assert_response :created
 end

 test "lead submission rechecks current landing page permission" do
  @pixel.update!(
    allowed_pages: [
      "https://example.com/form"
    ]
  )

  post "/visit",
    params: {
      pixel_id: @pixel.public_id,
      session_id: "permission-change-session",
      page_url: "https://example.com/form"
    },
    as: :json

  assert_response :created

  # Admin changes Pixel configuration after visit.
  @pixel.update!(
    allowed_pages: [
      "https://example.com/other-form"
    ]
  )

  post "/leads",
    params: {
      pixel_id: @pixel.public_id,
      session_id: "permission-change-session",
      lead_id: "permission-change-lead",
      fields: {
        first_name: "Test",
        last_name: "Lead",
        email: "test@example.com",
        phone: "5551112222"
      }
    },
    as: :json

  assert_response :forbidden
 end

 test "empty allowed pages permits any landing page" do
  @pixel.update!(
    allowed_pages: []
  )

  post "/visit",
    params: {
      pixel_id: @pixel.public_id,
      session_id: "open-session",
      page_url:
        "https://another-site.example/form"
    },
    as: :json

  assert_response :created
end
test "activity endpoint rejects incorrect session" do
  session =
    @pixel.pixel_sessions.create!(
      session_id: "activity-security-session",
      page_url: "https://example.com/landing",
      started_at: Time.current
    )

  lead =
    session.create_lead!(
      external_id: "activity-security-lead",
      first_name: "Jane",
      last_name: "Doe",
      email: "security@example.com",
      phone: "5559991111",
      landing_page_url: session.page_url,
      submitted_at: Time.current
    )

  get "/leads/#{lead.external_id}/activity",
      params: {
        session_id: "wrong-session-id"
      },
      as: :json

  assert_response :not_found
end
test "activity endpoint does not expose lead from another session" do
  first_session =
    @pixel.pixel_sessions.create!(
      session_id: "activity-first-session",
      page_url: "https://example.com/landing",
      started_at: Time.current
    )

  lead =
    first_session.create_lead!(
      external_id: "activity-private-lead",
      email: "private@example.com",
      phone: "5558881111",
      landing_page_url: first_session.page_url,
      submitted_at: Time.current
    )

  second_session =
    @pixel.pixel_sessions.create!(
      session_id: "activity-second-session",
      page_url: "https://example.com/landing",
      started_at: Time.current
    )

  get "/leads/#{lead.external_id}/activity",
      params: {
        session_id: second_session.session_id
      },
      as: :json

  assert_response :not_found
end
end