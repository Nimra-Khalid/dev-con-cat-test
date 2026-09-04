class LayerResult < ApplicationRecord
  EXECUTION_STATUSES = %w[
    pending
    completed
    failed
    not_enabled
    not_applicable
    insufficient_credits
  ].freeze

  VERDICTS = %w[
    pass
    warn
    fail
  ].freeze

  belongs_to :verification_run

  validates :layer_name,
            presence: true,
            uniqueness: {
              scope: :verification_run_id
            }

  validates :execution_status,
            inclusion: { in: EXECUTION_STATUSES }

  validates :verdict,
            inclusion: { in: VERDICTS },
            allow_nil: true

  validates :risk_score,
            numericality: {
              greater_than_or_equal_to: 0
            }

  validates :credit_cost,
            numericality: {
              greater_than_or_equal_to: 0
            }
end