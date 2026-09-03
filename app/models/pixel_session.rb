class PixelSession < ApplicationRecord
  belongs_to :pixel

  has_one :lead, dependent: :restrict_with_error

  validates :session_id,
            presence: true,
            uniqueness: true

  validates :page_url,
            presence: true

  validates :started_at,
            presence: true
end