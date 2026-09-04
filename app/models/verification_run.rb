class VerificationRun < ApplicationRecord
  STATUSES = %w[
    pending
    running
    completed
    failed
  ].freeze

  belongs_to :lead

  has_many :layer_results,
           dependent: :destroy

           
  has_one :verdict,
            dependent: :destroy

  has_many :credit_transactions,
         dependent: :destroy          

  validates :status,
            inclusion: { in: STATUSES }

  validates :policy_version,
            presence: true
end