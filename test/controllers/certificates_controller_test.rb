require "test_helper"

class CertificatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = Account.create!(
      external_id: "acct_certificate_test",
      company_name: "Certificate Test Account",
      plan: "growth",
      monthly_credit_allowance: 10_000,
      credits_used_this_cycle: 0,
      status: "active",
      avg_daily_burn: 100,
      enabled_modules: ["trustedform"]
    )

    @pixel = Pixel.create!(
      public_id: "px_certificate_test",
      account: @account,
      name: "Certificate Test Pixel",
      allowed_pages: [],
      enabled_modules: ["trustedform"],
      active: true
    )

    @pixel_session = PixelSession.create!(
      session_id: "session_certificate_test",
      pixel: @pixel,
      page_url: "https://example.test/landing",
      started_at: Time.current
    )

    @lead = Lead.create!(
      external_id: "lead_certificate_test",
      pixel_session: @pixel_session,
      first_name: "Jane",
      last_name: "Doe",
      email: "jane@example.com",
      phone: "15555550123",
      landing_page_url: "https://example.test/landing",
      submit_ip: "127.0.0.1",
      trusted_form_cert_url: "https://cert.trustedform.com/example",
      submitted_at: Time.current
    )

    @verification_run = VerificationRun.create!(
      lead: @lead,
      status: "completed",
      policy_version: "v1",
      started_at: 2.seconds.ago,
      completed_at: Time.current
    )

    @layer_result = LayerResult.create!(
      verification_run: @verification_run,
      layer_name: "trustedform",
      execution_status: "completed",
      verdict: "pass",
      risk_score: 0,
      reason: "TrustedForm certificate verified",
      raw_response: {
        "status" => "verified"
      },
      credit_cost: 1
    )

    @verdict = Verdict.create!(
      verification_run: @verification_run,
      decision: "ACCEPT",
      risk_score: 0,
      hard_stop: false,
      reasons: ["All required verification checks passed"],
      policy_snapshot: {
        "accept_below" => 25,
        "reject_at_or_above" => 60
      },
      decided_at: Time.current
    )

    @certificate =
      CertificateIssuer.new(@verification_run).call
  end

  test "certificate issuer creates certificate with evidence snapshot" do
    assert @certificate.persisted?
    assert @certificate.public_id.start_with?("cert_")

    assert_equal(
      @verification_run.id,
      @certificate.verification_run_id
    )

    assert_equal(
      @lead.trusted_form_cert_url,
      @certificate.trusted_form_reference
    )

    assert_equal(
      "ACCEPT",
      @certificate.evidence.dig("verdict", "decision")
    )

    assert_equal(
      @lead.external_id,
      @certificate.evidence.dig("lead", "external_id")
    )

    assert_equal(
      @pixel.public_id,
      @certificate.evidence.dig("pixel", "public_id")
    )

    assert @certificate.signature.present?
  end

  test "issuer is idempotent and does not create duplicate certificates" do
    second_certificate =
      CertificateIssuer.new(@verification_run).call

    assert_equal @certificate.id, second_certificate.id

    assert_equal(
      1,
      ConsentCertificate.where(
        verification_run: @verification_run
      ).count
    )
  end

  test "retrieving untouched certificate reports valid signature" do
    get "/certificates/#{@certificate.public_id}"

    assert_response :success

    body = JSON.parse(response.body)
    certificate = body["certificate"]

    assert_equal @certificate.public_id, certificate["public_id"]
    assert_equal true, certificate["valid"]

    assert_equal(
      "ACCEPT",
      certificate.dig("verdict", "decision")
    )
  end

  test "tampered evidence reports invalid signature" do
    tampered_evidence =
      @certificate.evidence.deep_dup

    tampered_evidence["verdict"]["decision"] = "REJECT"

    # update_column deliberately bypasses callbacks.
    #
    # This simulates a database-level attacker or accidental
    # out-of-band modification rather than normal Rails code.
    @certificate.update_column(
      :evidence,
      tampered_evidence
    )

    get "/certificates/#{@certificate.public_id}"

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal false, body.dig("certificate", "valid")
    assert_equal(
      "REJECT",
      body.dig(
        "certificate",
        "verdict",
        "decision"
      )
    )
  end

  test "certificate cannot be modified through normal application code" do
    original_signature = @certificate.signature

    result =
      @certificate.update(
        signature: "forged-signature"
      )

    assert_equal false, result

    @certificate.reload

    assert_equal(
      original_signature,
      @certificate.signature
    )

    assert_includes(
      @certificate.errors[:base],
      "Consent certificates are immutable"
    )
  end

  test "certificate cannot be destroyed through normal application code" do
  result = @certificate.destroy

  assert_equal false, result

  assert ConsentCertificate.exists?(
    @certificate.id
  )

  assert_includes(
    @certificate.errors[:base],
    "Consent certificates cannot be deleted"
  )
  end

  test "public certificate does not expose lead PII or raw provider responses" do
  get "/certificates/#{@certificate.public_id}",
      as: :json

  assert_response :success

  body = JSON.parse(response.body)

  certificate = body["certificate"]

  refute certificate.key?("evidence")

  serialized = certificate.to_json

  refute_includes serialized, @lead.email
  refute_includes serialized, @lead.phone
  refute_includes serialized, @lead.submit_ip.to_s
  refute_includes serialized, "raw_response"
end
end