require "openssl"
require "json"

class CertificateIssuer
  def initialize(verification_run)
    @verification_run = verification_run
    @lead = verification_run.lead
  end

  def call
    return verification_run.consent_certificate if verification_run.consent_certificate.present?

    evidence = build_evidence
    signature = sign(evidence)

    ConsentCertificate.create!(
      verification_run: verification_run,
      public_id: generate_public_id,
      trusted_form_reference: lead.trusted_form_cert_url,
      evidence: evidence,
      signature: signature,
      issued_at: Time.current
    )
  end

  private

  attr_reader :verification_run, :lead

  def build_evidence
    verdict = verification_run.verdict

    {
      certificate_version: "1.0",

      lead: {
        external_id: lead.external_id,
        first_name: lead.first_name,
        last_name: lead.last_name,
        email: lead.email,
        phone: lead.phone,
        submitted_at: lead.submitted_at&.iso8601,
        landing_page_url: lead.landing_page_url,
        submit_ip: lead.submit_ip
      },

      account: {
        external_id: lead.account.external_id,
        company_name: lead.account.company_name
      },

      pixel: {
        public_id: lead.pixel.public_id,
        name: lead.pixel.name
      },

      verification: {
        run_id: verification_run.id,
        policy_version: verification_run.policy_version,
        started_at: verification_run.started_at&.iso8601,
        completed_at: verification_run.completed_at&.iso8601
      },

      verdict: {
        decision: verdict.decision,
        risk_score: verdict.risk_score,
        hard_stop: verdict.hard_stop,
        reasons: verdict.reasons,
        decided_at: verdict.decided_at&.iso8601,
        policy_snapshot: verdict.policy_snapshot
      },

      layers: verification_run.layer_results.order(:id).map do |layer|
        {
          layer_name: layer.layer_name,
          execution_status: layer.execution_status,
          verdict: layer.verdict,
          risk_score: layer.risk_score,
          reason: layer.reason,
          credit_cost: layer.credit_cost,
          raw_response: layer.raw_response
        }
      end,

      trusted_form_reference: lead.trusted_form_cert_url
    }
  end

  def sign(evidence)
    OpenSSL::HMAC.hexdigest(
      "SHA256",
      signing_secret,
      canonical_json(evidence)
    )
  end

  def signing_secret
    Rails.application.secret_key_base
  end

  def canonical_json(value)
    deep_sort(value).to_json
  end

  def deep_sort(value)
    case value
    when Hash
      value
        .sort_by { |key, _| key.to_s }
        .to_h
        .transform_values { |nested| deep_sort(nested) }
    when Array
      value.map { |item| deep_sort(item) }
    else
      value
    end
  end

  def generate_public_id
    "cert_#{SecureRandom.uuid}"
  end
end