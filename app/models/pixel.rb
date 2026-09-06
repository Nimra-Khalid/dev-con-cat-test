class Pixel < ApplicationRecord
  belongs_to :account

  has_many :pixel_sessions,
           dependent: :restrict_with_error

  before_validation :generate_public_id, on: :create

  validates :public_id,
            presence: true,
            uniqueness: true

  validates :name,
            presence: true

  validates :active,
            inclusion: { in: [true, false] }

  validate :enabled_modules_must_belong_to_account

  private

  def generate_public_id
    return if public_id.present?

    self.public_id = "px_#{SecureRandom.uuid}"
  end

  def enabled_modules_must_belong_to_account
    return if account.nil?

    invalid_modules = enabled_modules - account.enabled_modules

    return if invalid_modules.empty?

    errors.add(
      :enabled_modules,
      "contains modules not enabled for the account: #{invalid_modules.join(', ')}"
    )
  end
end