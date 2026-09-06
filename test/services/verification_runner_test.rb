require "test_helper"

class VerificationRunnerTest < ActiveSupport::TestCase
  test "runs enabled verification modules and persists verdict" do
    account = Account.create!(
      external_id: "acct_test",
      company_name: "Test Account",
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

    pixel = account.pixels.create!(
      public_id: "px_test",
      name: "Test Pixel",
      allowed_pages: [],
      enabled_modules: [
        "anura",
        "trustedform",
        "dnc"
      ],
      active: true
    )

    session = pixel.pixel_sessions.create!(
      session_id: "session_test",
      page_url: "https://example.com",
      started_at: Time.current
    )

    lead = session.create_lead!(
      external_id: "L-1001",
      first_name: "Test",
      last_name: "Lead",
      email: "test@example.com",
      phone: "5551112222",
      landing_page_url: "https://example.com",
      submitted_at: Time.current
    )

    verdict = VerificationRunner.new(lead).call

    run = lead.verification_runs.last

    assert_equal "completed", run.status
    assert_equal 3, run.layer_results.count

    assert_equal "ACCEPT", verdict.decision
    assert_equal run.id, verdict.verification_run_id
    assert_equal "v1", run.policy_version

    assert_equal(
      %w[anura dnc trustedform],
      run.layer_results.pluck(:layer_name).sort
    )
  end

  test "does not charge for voice when voice is not applicable" do
  account = Account.create!(
    external_id: "acct_voice_test",
    company_name: "Voice Test Account",
    plan: "growth",
    monthly_credit_allowance: 100,
    credits_used_this_cycle: 0,
    status: "active",
    enabled_modules: [
      "voice"
    ]
  )

  pixel = account.pixels.create!(
    public_id: "px_voice_test",
    name: "Voice Test Pixel",
    allowed_pages: [],
    enabled_modules: [
      "voice"
    ],
    active: true
  )

  session = pixel.pixel_sessions.create!(
    session_id: "session_voice_test",
    page_url: "https://example.com",
    started_at: Time.current
  )

  lead = session.create_lead!(
    external_id: "voice-lead-test",
    fixture_key: "L-1001",
    first_name: "Voice",
    last_name: "Lead",
    email: "voice@example.com",
    phone: "5551113333",
    landing_page_url: "https://example.com",
    submitted_at: Time.current
  )

  before_used =
    account.credits_used_this_cycle

  VerificationRunner.new(lead).call

  run =
    lead.verification_runs.order(:created_at).last

  voice_result =
    run.layer_results.find_by!(
      layer_name: "voice"
    )

  assert_equal(
    "not_applicable",
    voice_result.execution_status
  )

  assert_equal(
    0,
    voice_result.credit_cost
  )

  voice_transaction =
    run.credit_transactions.find_by(
      layer_name: "voice"
    )

  assert_nil voice_transaction

  account.reload

  assert_equal(
    before_used,
    account.credits_used_this_cycle
  )
  end

  test "marks unaffordable layers insufficient while continuing affordable checks" do
  account = Account.create!(
    external_id: "acct_low_credit_test",
    company_name: "Low Credit Test",
    plan: "starter",
    monthly_credit_allowance: 4,
    credits_used_this_cycle: 0,
    status: "active",
    enabled_modules: [
      "anura",
      "phone_validation",
      "dnc"
    ]
  )

  pixel = account.pixels.create!(
    public_id: "px_low_credit_test",
    name: "Low Credit Pixel",
    allowed_pages: [],
    enabled_modules: [
      "anura",
      "phone_validation",
      "dnc"
    ],
    active: true
  )

  session = pixel.pixel_sessions.create!(
    session_id: "session_low_credit_test",
    page_url: "https://example.com",
    started_at: Time.current
  )

  lead = session.create_lead!(
    external_id: "low-credit-lead",
    fixture_key: "L-1001",
    first_name: "Low",
    last_name: "Credit",
    email: "lowcredit@example.com",
    phone: "5551114444",
    landing_page_url: "https://example.com",
    submitted_at: Time.current
  )

  verdict = VerificationRunner.new(lead).call

  run = lead.verification_runs.last

  anura =
    run.layer_results.find_by!(
      layer_name: "anura"
    )

  phone =
    run.layer_results.find_by!(
      layer_name: "phone_validation"
    )

  dnc =
    run.layer_results.find_by!(
      layer_name: "dnc"
    )

  assert_equal "completed",
               anura.execution_status

  assert_equal "insufficient_credits",
               phone.execution_status

  assert_equal "completed",
               dnc.execution_status

  assert_equal 3,
               run.layer_results.count

  assert_equal 2,
               run.credit_transactions.count

  account.reload

  assert_equal 3,
               account.credits_used_this_cycle

  assert_equal "REVIEW",
               verdict.decision
 end
end