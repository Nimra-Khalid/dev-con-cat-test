class Verdict < ApplicationRecord
  DECISIONS = %w[
    ACCEPT
    REVIEW
    REJECT
  ].freeze

  belongs_to :verification_run

  validates :verification_run_id,
            uniqueness: true

  validates :decision,
            presence: true,
            inclusion: { in: DECISIONS }

  validates :risk_score,
            numericality: {
              greater_than_or_equal_to: 0
            }

  validates :decided_at,
            presence: true
end