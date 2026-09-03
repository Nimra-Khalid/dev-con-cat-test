class Account < ApplicationRecord

  has_many :users, dependent: :restrict_with_error

  validates :external_id,
            presence: true,
            uniqueness: true

  validates :company_name,
            presence: true

  validates :plan,
            presence: true

  validates :status,
            presence: true

  validates :monthly_credit_allowance,
            numericality: {
              greater_than_or_equal_to: 0
            }

  validates :credits_used_this_cycle,
            numericality: {
              greater_than_or_equal_to: 0
            }

  def credits_remaining
    monthly_credit_allowance - credits_used_this_cycle
  end
end