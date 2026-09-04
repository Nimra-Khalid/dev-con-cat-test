class ConsensusEngine
  ACCEPT_THRESHOLD = 25
  REJECT_THRESHOLD = 60

  HARD_STOP_LAYERS = {
    "blacklist_alliance" => {
      fail_values: %w[litigator]
    },
    "dnc" => {
      fail_values: %w[dnc_listed internal_dnc]
    },
    "trustedform" => {
      fail_values: %w[mismatch expired]
    },
    "duplicate_detection" => {
      fail_values: %w[exact_duplicate]
    }
  }.freeze

  def initialize(verification_run)
    @verification_run = verification_run
    @score = 0
    @reasons = []
    @hard_stop = false
  end

  def call
    process_layer_results

    {
      decision: decision,
      score: @score,
      hard_stop: @hard_stop,
      reasons: @reasons
    }
  end

  private

  attr_reader :verification_run

  def process_layer_results
    verification_run.layer_results.each do |result|
      next unless result.execution_status == "completed"

      process_hard_stop(result)
      process_weighted_signal(result)
    end
  end

  def process_hard_stop(result)
    config = HARD_STOP_LAYERS[result.layer_name]

    return unless config

    provider_value = normalized_provider_value(result)

    return unless config[:fail_values].include?(provider_value)

    @hard_stop = true
    @reasons << hard_stop_reason(result.layer_name, provider_value)
  end

  def process_weighted_signal(result)
    case result.layer_name
    when "anura"
      score_anura(result)

    when "vpn_proxy"
      score_vpn_proxy(result)

    when "phone_validation"
      score_phone_validation(result)

    when "email_validation"
      score_email_validation(result)

    when "blacklist_alliance"
      score_blacklist(result)

    when "enrichment"
      score_enrichment(result)

    when "duplicate_detection"
      score_duplicate(result)

    when "voice"
      score_voice(result)
    end
  end

  def score_anura(result)
    value = normalized_provider_value(result)

    case value
    when "suspect"
      add_risk(20, "Anura marked the lead as suspect")
    when "bad"
      add_risk(45, "Anura marked the lead as bad")
    end
  end

  def score_vpn_proxy(result)
    risk = raw_value(result, "risk")

    case risk
    when "medium"
      add_risk(15, "Medium VPN/proxy risk")
    when "high"
      add_risk(30, "High VPN/proxy risk")
    end
  end

  def score_phone_validation(result)
    raw = result.raw_response || {}

    if truthy?(raw["provider_disagreement"])
      add_risk(20, "Phone validation providers disagree")
    end

    if truthy?(raw["majority_invalid"])
      add_risk(35, "Most phone validation providers marked the number invalid")
    end

    if truthy?(raw["voip_only"])
      add_risk(15, "Phone number appears to be VoIP")
    end
  end

  def score_email_validation(result)
    raw = result.raw_response || {}

    if truthy?(raw["both_undeliverable"])
      add_risk(35, "Both email providers marked the address undeliverable")
    end

    if truthy?(raw["disposable"])
      add_risk(30, "Disposable email address detected")
    end

    fraud_score = raw["fraud_score"].to_f

    if fraud_score >= 0.8
      add_risk(20, "High email fraud score")
    end
  end

  def score_blacklist(result)
    value = normalized_provider_value(result)

    if value == "suspected"
      add_risk(25, "Lead is suspected on blacklist data")
    end
  end

  def score_enrichment(result)
    raw = result.raw_response || {}

    if truthy?(raw["provider_disagreement"])
      add_risk(20, "Enrichment providers disagree")
    end

    if truthy?(raw["poor_match"])
      add_risk(20, "Enrichment data poorly matches the submitted lead")
    end
  end

  def score_duplicate(result)
    value = normalized_provider_value(result)

    if value == "soft_duplicate"
      add_risk(10, "Possible duplicate lead detected")
    end
  end

  def score_voice(result)
    value = normalized_provider_value(result)

    if %w[human_reused_actor synthetic].include?(value)
      add_risk(40, "Voice verification indicates reused or synthetic audio")
    end
  end

  def decision
    return "REJECT" if @hard_stop
    return "REJECT" if @score >= REJECT_THRESHOLD
    return "REVIEW" if @score >= ACCEPT_THRESHOLD

    "ACCEPT"
  end

  def add_risk(points, reason)
    @score += points
    @reasons << reason
  end

  def normalized_provider_value(result)
    raw = result.raw_response || {}

    raw["status"] ||
      raw["verdict"] ||
      raw["result"] ||
      raw["classification"]
  end

  def raw_value(result, key)
    (result.raw_response || {})[key]
  end

  def truthy?(value)
    value == true || value == "true"
  end

  def hard_stop_reason(layer_name, value)
    case layer_name
    when "blacklist_alliance"
      "Confirmed litigator detected"
    when "dnc"
      "Lead cannot be contacted due to DNC status"
    when "trustedform"
      "TrustedForm consent validation failed: #{value}"
    when "duplicate_detection"
      "Exact duplicate lead detected"
    else
      "Hard-stop verification rule triggered"
    end
  end
end