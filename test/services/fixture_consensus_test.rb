require "test_helper"
require "json"

class FixtureConsensusTest < ActiveSupport::TestCase
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

  EXPECTED = {
    "L-1001" => "ACCEPT",
    "L-1002" => "REJECT",
    "L-1003" => "REVIEW",
    "L-1004" => "REJECT",
    "L-1005" => "REJECT",
    "L-1006" => "REJECT",
    "L-1007" => "REVIEW",
    "L-1008" => "REVIEW",
    "L-1009" => "REJECT",
    "L-1010" => "REJECT",
    "L-1011" => "REVIEW",
    "L-1012" => "ACCEPT"
  }.freeze

  def setup
  @provider_data = {}

  PROVIDER_FILES.each do |layer_name, filename|
    path = Rails.root.join(
      "mock-data",
      "providers",
      filename
    )

    file_data = JSON.parse(File.read(path))

    @provider_data[layer_name] =
      file_data.fetch("results", {})
  end
end

  test "real fixture scenarios produce expected consensus verdicts" do
    EXPECTED.each do |lead_id, expected_decision|
      run = build_verification_run(lead_id)

      result = ConsensusEngine.new(run).call

      assert_equal(
        expected_decision,
        result[:decision],
        "#{lead_id} expected #{expected_decision}, " \
        "got #{result[:decision]} " \
        "with score #{result[:score]} " \
        "and reasons #{result[:reasons].inspect}"
      )
    end
  end

  private

  def build_verification_run(lead_id)
    run = VerificationRun.new(
      status: "completed",
      policy_version: "v1"
    )

    PROVIDER_FILES.each_key do |layer_name|
      raw = @provider_data.dig(layer_name, lead_id)

      next if raw.nil?

      normalized =
        ProviderResultNormalizer
          .new(layer_name, raw)
          .call

      execution_status =
        execution_status_for(layer_name, normalized)

      run.layer_results.build(
        layer_name: layer_name,
        execution_status: execution_status,
        verdict: normalized["verdict"],
        risk_score: 0,
        credit_cost: 0,
        raw_response: normalized
      )
    end

    add_duplicate_result(run, lead_id)

    run
  end

  def execution_status_for(layer_name, normalized)
    if layer_name == "voice" &&
       normalized["applicable"] == false
      "not_applicable"
    else
      "completed"
    end
  end

  def add_duplicate_result(run, lead_id)
    status =
      case lead_id
      when "L-1004"
        "exact_duplicate"
      when "L-1012"
        "soft_duplicate"
      else
        "unique"
      end

    run.layer_results.build(
      layer_name: "duplicate_detection",
      execution_status: "completed",
      verdict: status == "unique" ? "pass" : "warn",
      risk_score: 0,
      credit_cost: 0,
      raw_response: {
        "status" => status
      }
    )
  end
end