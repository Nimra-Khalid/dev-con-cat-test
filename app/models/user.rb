class User < ApplicationRecord
  has_secure_password

  belongs_to :account, optional: true

  ROLES = %w[super_admin account_admin member].freeze

  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :role, presence: true, inclusion: { in: ROLES }

  validate :account_required_for_non_super_admin

  def super_admin?
    role == "super_admin"
  end

  def account_admin?
    role == "account_admin"
  end

  def member?
    role == "member"
  end

  private

  def account_required_for_non_super_admin
    if role != "super_admin" && account.nil?
      errors.add(:account, "must be present for non-super-admin users")
    end
  end
end