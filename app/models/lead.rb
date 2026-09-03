class Lead < ApplicationRecord
  belongs_to :pixel_session

  validates :external_id,
            presence: true,
            uniqueness: true

  validates :pixel_session_id,
            uniqueness: true

  validates :landing_page_url,
            presence: true

  validates :submitted_at,
            presence: true

  validates :form_dwell_ms,
            numericality: {
              greater_than_or_equal_to: 0
            },
            allow_nil: true

  def pixel
    pixel_session.pixel
  end

  def account
    pixel.account
  end
end