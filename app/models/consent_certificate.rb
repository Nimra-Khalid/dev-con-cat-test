class ConsentCertificate < ApplicationRecord
  belongs_to :verification_run

  validates :public_id, presence: true, uniqueness: true
  validates :evidence, presence: true
  validates :signature, presence: true
  validates :issued_at, presence: true
  validates :verification_run_id, uniqueness: true

  before_update :prevent_modification
  before_destroy :prevent_destruction

  private

  def prevent_modification
    errors.add(:base, "Consent certificates are immutable")
    throw(:abort)
  end

  def prevent_destruction
    errors.add(:base, "Consent certificates cannot be deleted")
    throw(:abort)
  end
end