require "json"

class VerificationRunner
  POLICY_VERSION = "v1"

  PROVIDER_FILES = {
    "anura" => "anura.json",
    "trustedform" => "trustedform.json",
    "dnc" => "dnc.json",
    "blacklist_alliance" => "blacklist_alliance.json",
    "phone_validation" => "phone_validation.json",
    "email_validation" => "email_validation.json",
    "vpn_proxy" => "vpn_proxy.json",
    "enrichment" => "enrichment.json",
    "voice" => "voice.json"
  }.freeze

  def initialize(lead)
    @lead = lead
  end

  def call
    verification_run = lead.verification_runs.create!(
      status: "running",
      policy_version: POLICY_VERSION,
      started_at: Time.current
    )

    process_modules(verification_run)

    consensus = ConsensusEngine.new(verification_run).call

    verdict = verification_run.create_verdict!(
      decision: consensus[:decision],
      risk_score: consensus[:score],
      hard_stop: consensus[:hard_stop],
      reasons: consensus[:reasons],
      policy_snapshot: policy_snapshot,
      decided_at: Time.current
    )

    verification_run.update!(
      status: "completed",
      completed_at: Time.current
    )

    verdict
  rescue StandardError
    verification_run&.update(
      status: "failed",
      completed_at: Time.current
    )

    raise
  end

  private

  attr_reader :lead

  def process_modules(verification_run)
    credit_manager =
      CreditManager.new(
        lead.account,
        verification_run
      )

    enabled_modules.each do |layer_name|
      unless credit_manager.charge!(layer_name)
        create_insufficient_credit_result(
          verification_run,
          layer_name,
          credit_manager.cost_for(layer_name)
        )

        next
      end

      if layer_name == "duplicate_detection"
        process_duplicate_layer(verification_run)
      else
        process_provider_layer(
          verification_run,
          layer_name
        )
      end
    end
  end

  def enabled_modules
    lead.pixel.enabled_modules
  end

  def process_provider_layer(
    verification_run,
    layer_name
  )
    filename = PROVIDER_FILES[layer_name]

    unless filename
      create_failed_result(
        verification_run,
        layer_name,
        "No provider adapter configured"
      )

      return
    end

    raw = provider_response(
      filename,
      lead.external_id
    )

    unless raw
      create_failed_result(
        verification_run,
        layer_name,
        "No mock provider response found"
      )

      return
    end

    normalized =
      ProviderResultNormalizer
        .new(layer_name, raw)
        .call

    execution_status =
      if layer_name == "voice" &&
         normalized["applicable"] == false
        "not_applicable"
      else
        "completed"
      end

    verification_run.layer_results.create!(
      layer_name: layer_name,
      execution_status: execution_status,
      verdict: normalized["verdict"],
      risk_score: 0,
      credit_cost:
        CreditManager::MODULE_COSTS.fetch(
          layer_name,
          0
        ),
      raw_response: normalized
    )
  rescue StandardError => e
    create_failed_result(
      verification_run,
      layer_name,
      e.message
    )
  end

  def process_duplicate_layer(verification_run)
    duplicate_status = duplicate_status_for_lead

    verdict =
      case duplicate_status
      when "exact_duplicate"
        "fail"
      when "soft_duplicate"
        "warn"
      else
        "pass"
      end

    verification_run.layer_results.create!(
      layer_name: "duplicate_detection",
      execution_status: "completed",
      verdict: verdict,
      risk_score: 0,
      credit_cost:
        CreditManager::MODULE_COSTS.fetch(
          "duplicate_detection",
          0
        ),
      raw_response: {
        "status" => duplicate_status
      }
    )
  end

  def duplicate_status_for_lead
    account_leads =
      Lead
        .joins(pixel_session: { pixel: :account })
        .where(
          pixels: {
            account_id: lead.account.id
          }
        )
        .where.not(id: lead.id)

    exact_duplicate =
      account_leads.exists?(
        phone: lead.phone,
        email: lead.email
      )

    return "exact_duplicate" if exact_duplicate

    soft_duplicate =
      account_leads
        .where(phone: lead.phone)
        .where.not(email: lead.email)
        .exists?

    return "soft_duplicate" if soft_duplicate

    "unique"
  end

  def provider_response(
    filename,
    lead_id
  )
    path = Rails.root.join(
      "mock-data",
      "providers",
      filename
    )

    file_data =
      JSON.parse(
        File.read(path)
      )

    file_data
      .fetch("results", {})
      .fetch(lead_id, nil)
  end

  def create_failed_result(
    verification_run,
    layer_name,
    reason
  )
    verification_run.layer_results.create!(
      layer_name: layer_name,
      execution_status: "failed",
      verdict: nil,
      risk_score: 0,
      credit_cost: 0,
      reason: reason,
      raw_response: {}
    )
  end

  def create_insufficient_credit_result(
    verification_run,
    layer_name,
    required_credits
  )
    verification_run.layer_results.create!(
      layer_name: layer_name,
      execution_status: "insufficient_credits",
      verdict: nil,
      risk_score: 0,
      credit_cost: 0,
      reason:
        "Verification requires #{required_credits} credits, " \
        "but the account does not have enough remaining.",
      raw_response: {}
    )
  end

  def policy_snapshot
    {
      version: POLICY_VERSION,
      accept_threshold:
        ConsensusEngine::ACCEPT_THRESHOLD,
      reject_threshold:
        ConsensusEngine::REJECT_THRESHOLD
    }
  end
end

