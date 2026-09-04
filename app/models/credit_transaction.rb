class CreditTransaction < ApplicationRecord
  belongs_to :account
  belongs_to :verification_run

  validates :layer_name, presence: true

  validates :amount,
            numericality: {
              greater_than: 0
            }

  validates :transaction_type,
            presence: true

  validates :layer_name,
            uniqueness: {
              scope: :verification_run_id
            }
end