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
end