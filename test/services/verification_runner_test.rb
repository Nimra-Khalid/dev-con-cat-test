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

 test "detects recent exact duplicate within the same account" do
  account = Account.create!(
    external_id: "acct_duplicate_recent",
    company_name: "Recent Duplicate Account",
    plan: "growth",
    monthly_credit_allowance: 100,
    credits_used_this_cycle: 0,
    status: "active",
    enabled_modules: [
      "duplicate_detection"
    ]
  )

  pixel = account.pixels.create!(
    public_id: "px_duplicate_recent",
    name: "Duplicate Pixel",
    allowed_pages: [],
    enabled_modules: [
      "duplicate_detection"
    ],
    active: true
  )

  first_session = pixel.pixel_sessions.create!(
    session_id: "session_duplicate_first",
    page_url: "https://example.com",
    started_at: 2.days.ago
  )

  first_session.create_lead!(
    external_id: "duplicate-original",
    first_name: "Original",
    last_name: "Lead",
    email: "duplicate@example.com",
    phone: "5559991111",
    landing_page_url: "https://example.com",
    submitted_at: 2.days.ago
  )

  second_session = pixel.pixel_sessions.create!(
    session_id: "session_duplicate_second",
    page_url: "https://example.com",
    started_at: Time.current
  )

  lead = second_session.create_lead!(
    external_id: "duplicate-new",
    first_name: "New",
    last_name: "Lead",
    email: "duplicate@example.com",
    phone: "5559991111",
    landing_page_url: "https://example.com",
    submitted_at: Time.current
  )

  VerificationRunner.new(lead).call

  result =
    lead.verification_runs
        .last
        .layer_results
        .find_by!(
          layer_name: "duplicate_detection"
        )

  assert_equal "fail", result.verdict

  assert_equal(
    "exact_duplicate",
    result.raw_response["status"]
  )
 end

 test "ignores duplicates older than thirty days" do
  account = Account.create!(
    external_id: "acct_duplicate_old",
    company_name: "Old Duplicate Account",
    plan: "growth",
    monthly_credit_allowance: 100,
    credits_used_this_cycle: 0,
    status: "active",
    enabled_modules: [
      "duplicate_detection"
    ]
  )

  pixel = account.pixels.create!(
    public_id: "px_duplicate_old",
    name: "Old Duplicate Pixel",
    allowed_pages: [],
    enabled_modules: [
      "duplicate_detection"
    ],
    active: true
  )

  old_session = pixel.pixel_sessions.create!(
    session_id: "session_duplicate_old",
    page_url: "https://example.com",
    started_at: 45.days.ago
  )

  old_session.create_lead!(
    external_id: "duplicate-old-original",
    first_name: "Old",
    last_name: "Lead",
    email: "oldduplicate@example.com",
    phone: "5558882222",
    landing_page_url: "https://example.com",
    submitted_at: 45.days.ago
  )

  new_session = pixel.pixel_sessions.create!(
    session_id: "session_duplicate_new",
    page_url: "https://example.com",
    started_at: Time.current
  )

  lead = new_session.create_lead!(
    external_id: "duplicate-current",
    first_name: "Current",
    last_name: "Lead",
    email: "oldduplicate@example.com",
    phone: "5558882222",
    landing_page_url: "https://example.com",
    submitted_at: Time.current
  )

  VerificationRunner.new(lead).call

  result =
    lead.verification_runs
        .last
        .layer_results
        .find_by!(
          layer_name: "duplicate_detection"
        )

  assert_equal "pass", result.verdict

  assert_equal(
    "unique",
    result.raw_response["status"]
  )
 end

 test "does not treat a lead from another account as a duplicate" do
  # Account A already has a lead with this phone/email.
  first_account = Account.create!(
    external_id: "acct_duplicate_tenant_a",
    company_name: "Tenant A",
    plan: "growth",
    monthly_credit_allowance: 100,
    credits_used_this_cycle: 0,
    status: "active",
    enabled_modules: [
      "duplicate_detection"
    ]
  )

  first_pixel = first_account.pixels.create!(
    public_id: "px_duplicate_tenant_a",
    name: "Tenant A Pixel",
    allowed_pages: [],
    enabled_modules: [
      "duplicate_detection"
    ],
    active: true
  )

  first_session = first_pixel.pixel_sessions.create!(
    session_id: "session_duplicate_tenant_a",
    page_url: "https://tenant-a.example.com",
    started_at: 1.day.ago
  )

  first_session.create_lead!(
    external_id: "tenant-a-existing-lead",
    first_name: "Existing",
    last_name: "Lead",
    email: "shared@example.com",
    phone: "5557773333",
    landing_page_url: "https://tenant-a.example.com",
    submitted_at: 1.day.ago
  )

  # Account B receives an identical lead.
  second_account = Account.create!(
    external_id: "acct_duplicate_tenant_b",
    company_name: "Tenant B",
    plan: "growth",
    monthly_credit_allowance: 100,
    credits_used_this_cycle: 0,
    status: "active",
    enabled_modules: [
      "duplicate_detection"
    ]
  )

  second_pixel = second_account.pixels.create!(
    public_id: "px_duplicate_tenant_b",
    name: "Tenant B Pixel",
    allowed_pages: [],
    enabled_modules: [
      "duplicate_detection"
    ],
    active: true
  )

  second_session = second_pixel.pixel_sessions.create!(
    session_id: "session_duplicate_tenant_b",
    page_url: "https://tenant-b.example.com",
    started_at: Time.current
  )

  lead = second_session.create_lead!(
    external_id: "tenant-b-new-lead",
    first_name: "New",
    last_name: "Lead",
    email: "shared@example.com",
    phone: "5557773333",
    landing_page_url: "https://tenant-b.example.com",
    submitted_at: Time.current
  )

  VerificationRunner.new(lead).call

  result =
    lead.verification_runs
        .last
        .layer_results
        .find_by!(
          layer_name: "duplicate_detection"
        )

  assert_equal "completed",
               result.execution_status

  assert_equal "pass",
               result.verdict

  assert_equal(
    "unique",
    result.raw_response["status"]
  )
end
end