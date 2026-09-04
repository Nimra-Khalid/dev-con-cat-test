class ProviderResultNormalizer
  def initialize(layer_name, raw_response)
    @layer_name = layer_name
    @raw = raw_response || {}
  end

  def call
    case layer_name
    when "anura"
      normalize_anura
    when "vpn_proxy"
      normalize_vpn_proxy
    when "trustedform"
      normalize_trustedform
    when "blacklist_alliance"
      normalize_blacklist
    when "dnc"
      normalize_dnc
    when "phone_validation"
      normalize_phone
    when "email_validation"
      normalize_email
    when "enrichment"
      normalize_enrichment
    when "voice"
      normalize_voice
    else
      default_result
    end
  end

  private

  attr_reader :layer_name, :raw

  def normalize_anura
    result = raw["result"]

    {
      "status" => result,
      "verdict" => case result
                   when "good" then "pass"
                   when "suspect" then "warn"
                   when "bad" then "fail"
                   end,
      "rule_ids" => raw["rule_ids"] || [],
      "confidence" => raw["confidence"],
      "original" => raw
    }
  end

  def normalize_vpn_proxy
    {
      "risk" => raw["risk"],
      "is_vpn" => raw["is_vpn"],
      "is_proxy" => raw["is_proxy"],
      "is_tor" => raw["is_tor"],
      "is_datacenter" => raw["is_datacenter"],
      "ip_mismatch" => raw["site_visit_ip_matches_submit_ip"] == false,
      "verdict" => raw["risk"] == "low" ? "pass" : "warn",
      "original" => raw
    }
  end

  def normalize_trustedform
    status = raw["status"]

    {
      "status" => status,
      "verdict" => status == "verified" ? "pass" : "fail",
      "matches_phone" => raw["matches_phone"],
      "matches_email" => raw["matches_email"],
      "page_url" => raw["page_url"],
      "consent_language_present" => raw["consent_language_present"],
      "expires_at" => raw["expires_at"],
      "original" => raw
    }
  end

  def normalize_blacklist
    status = raw["status"]

    {
      "status" => status,
      "verdict" => case status
                   when "clean" then "pass"
                   when "suspected" then "warn"
                   when "litigator" then "fail"
                   end,
      "match_score" => raw["match_score"],
      "original" => raw
    }
  end

  def normalize_dnc
    status = raw["dnc_status"]

    {
      # Important:
      # ConsensusEngine expects a normalized "status".
      "status" => status,

      "verdict" => status == "callable" ? "pass" : "fail",

      "callback_window_open" => raw["callback_window_open"],
      "national_dnc" => raw["national_dnc"],
      "state_dnc" => raw["state_dnc"],
      "internal_dnc" => raw["internal_dnc"],
      "original" => raw
    }
  end

  def normalize_phone
    providers = raw.fetch("providers", {})
    results = providers.values.select do |provider|
      provider.is_a?(Hash)
    end

    valid_count = results.count { |provider| provider["valid"] == true }
    invalid_count = results.count { |provider| provider["valid"] == false }

    line_types = results.map { |provider| provider["line_type"] }.compact

    provider_disagreement =
      valid_count.positive? && invalid_count.positive?

    majority_invalid =
      invalid_count > valid_count

    all_voip =
      line_types.any? && line_types.all? { |type| type == "voip" }

    {
      "provider_disagreement" => provider_disagreement,
      "majority_invalid" => majority_invalid,
      "voip_only" => all_voip,
      "valid_count" => valid_count,
      "invalid_count" => invalid_count,
      "line_types" => line_types,
      "verdict" => phone_verdict(
        provider_disagreement,
        majority_invalid,
        all_voip
      ),
      "original" => raw
    }
  end

  def normalize_email
    providers = raw.fetch("providers", {})
    results = providers.values.select do |provider|
      provider.is_a?(Hash)
    end
    deliverable_count =
      results.count { |provider| provider["deliverable"] == true }

    undeliverable_count =
      results.count { |provider| provider["deliverable"] == false }

    both_undeliverable =
      results.size >= 2 && undeliverable_count == results.size

    provider_disagreement =
      deliverable_count.positive? && undeliverable_count.positive?

    disposable =
      results.any? { |provider| provider["disposable"] == true }

    fraud_scores =
      results.map { |provider| provider["fraud_score"].to_i }

    max_fraud_score = fraud_scores.max || 0

    {
      "both_undeliverable" => both_undeliverable,
      "provider_disagreement" => provider_disagreement,
      "disposable" => disposable,
      "fraud_score" => max_fraud_score,
      "verdict" => if both_undeliverable
                     "warn"
                   elsif provider_disagreement
                     "warn"
                   elsif disposable
                     "warn"
                   else
                     "pass"
                   end,
      "original" => raw
    }
  end

  def normalize_enrichment
    audience = raw["audiencelabs"] || {}
    bytemine = raw["bytemine"] || {}

    both_matched =
      audience["matched"] == true &&
      bytemine["matched"] == true

    both_match_lead =
      audience["match_to_lead"] == true &&
      bytemine["match_to_lead"] == true

    addresses_disagree =
      both_matched &&
      audience["address"].present? &&
      bytemine["address"].present? &&
      audience["address"] != bytemine["address"]

    identity_disagreement =
      audience["match_to_lead"] != bytemine["match_to_lead"]

    provider_disagreement =
      addresses_disagree || identity_disagreement

    poor_match =
      audience["match_to_lead"] == false &&
      bytemine["match_to_lead"] == false

    {
      "provider_disagreement" => provider_disagreement,
      "poor_match" => poor_match,
      "both_match_lead" => both_match_lead,
      "verdict" => if poor_match || provider_disagreement
                     "warn"
                   else
                     "pass"
                   end,
      "original" => raw
    }
  end

  def normalize_voice
    unless raw["has_sample"]
      return {
        "applicable" => false,
        "verdict" => nil,
        "original" => raw
      }
    end

    voice_verdict = raw["verdict"]

    {
      "applicable" => true,
      "status" => voice_verdict,
      "verdict" => case voice_verdict
                   when "human_unique" then "pass"
                   when "human_reused_actor", "synthetic" then "fail"
                   end,
      "original" => raw
    }
  end

  def phone_verdict(disagreement, majority_invalid, all_voip)
    return "fail" if majority_invalid
    return "warn" if disagreement || all_voip

    "pass"
  end

  def default_result
    {
      "verdict" => nil,
      "original" => raw
    }
  end
end