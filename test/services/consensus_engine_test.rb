require "test_helper"

class ConsensusEngineTest < ActiveSupport::TestCase
  def build_run(layer_results)
    run = VerificationRun.new(
      status: "completed",
      policy_version: "v1"
    )

    layer_results.each do |attributes|
      run.layer_results.build(
        {
          execution_status: "completed",
          risk_score: 0,
          credit_cost: 0,
          raw_response: {}
        }.merge(attributes)
      )
    end

    run
  end

  test "accepts a clean lead" do
    run = build_run([
      {
        layer_name: "anura",
        raw_response: {
          "verdict" => "good"
        }
      },
      {
        layer_name: "vpn_proxy",
        raw_response: {
          "risk" => "low"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "ACCEPT", result[:decision]
    assert_equal 0, result[:score]
    assert_equal false, result[:hard_stop]
    assert_empty result[:reasons]
  end

  test "reviews lead when weighted risk reaches review threshold" do
    run = build_run([
      {
        layer_name: "anura",
        raw_response: {
          "verdict" => "suspect"
        }
      },
      {
        layer_name: "vpn_proxy",
        raw_response: {
          "risk" => "medium"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "REVIEW", result[:decision]
    assert_equal 35, result[:score]
    assert_equal false, result[:hard_stop]

    assert_includes result[:reasons],
                    "Anura marked the lead as suspect"

    assert_includes result[:reasons],
                    "Medium VPN/proxy risk"
  end

  test "rejects lead when weighted score reaches reject threshold" do
    run = build_run([
      {
        layer_name: "anura",
        raw_response: {
          "verdict" => "bad"
        }
      },
      {
        layer_name: "vpn_proxy",
        raw_response: {
          "risk" => "high"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "REJECT", result[:decision]
    assert_equal 75, result[:score]
    assert_equal false, result[:hard_stop]
  end

  test "rejects immediately for confirmed litigator hard stop" do
    run = build_run([
      {
        layer_name: "blacklist_alliance",
        raw_response: {
          "status" => "litigator"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "REJECT", result[:decision]
    assert_equal true, result[:hard_stop]

    assert_includes result[:reasons],
                    "Confirmed litigator detected"
  end

  test "rejects for DNC hard stop" do
    run = build_run([
      {
        layer_name: "dnc",
        raw_response: {
          "status" => "dnc_listed"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "REJECT", result[:decision]
    assert_equal true, result[:hard_stop]

    assert_includes result[:reasons],
                    "Lead cannot be contacted due to DNC status"
  end

  test "rejects for TrustedForm mismatch" do
    run = build_run([
      {
        layer_name: "trustedform",
        raw_response: {
          "status" => "mismatch"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "REJECT", result[:decision]
    assert_equal true, result[:hard_stop]

    assert_includes result[:reasons],
                    "TrustedForm consent validation failed: mismatch"
  end

  test "rejects an exact duplicate as a hard stop" do
    run = build_run([
      {
        layer_name: "duplicate_detection",
        raw_response: {
          "status" => "exact_duplicate"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "REJECT", result[:decision]
    assert_equal true, result[:hard_stop]

    assert_includes result[:reasons],
                    "Exact duplicate lead detected"
  end

  test "soft duplicate contributes risk but does not reject clean lead" do
    run = build_run([
      {
        layer_name: "duplicate_detection",
        raw_response: {
          "status" => "soft_duplicate"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "ACCEPT", result[:decision]
    assert_equal 10, result[:score]
    assert_equal false, result[:hard_stop]
  end

  test "does not score layers that did not complete" do
    run = build_run([
      {
        layer_name: "anura",
        execution_status: "failed",
        raw_response: {
          "verdict" => "bad"
        }
      },
      {
        layer_name: "vpn_proxy",
        execution_status: "not_enabled",
        raw_response: {
          "risk" => "high"
        }
      }
    ])

    result = ConsensusEngine.new(run).call

    assert_equal "ACCEPT", result[:decision]
    assert_equal 0, result[:score]
    assert_equal false, result[:hard_stop]
  end
end