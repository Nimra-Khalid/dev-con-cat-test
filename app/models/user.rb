class User < ApplicationRecord
  ROLES = %w[
    super_admin
    account_admin
    member
  ].freeze

  belongs_to :account, optional: true

  validates :external_id,
            presence: true,
            uniqueness: true

  validates :name,
            presence: true

  validates :email,
            presence: true,
            uniqueness: true

  validates :role,
            presence: true,
            inclusion: { in: ROLES }

  validate :account_required_for_tenant_users

  private

  def account_required_for_tenant_users
    return if role == "super_admin"

    errors.add(:account, "must be present") if account.nil?
  end
end