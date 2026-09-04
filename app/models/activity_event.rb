class ActivityEvent < ApplicationRecord
  EVENT_TYPES = %w[
    verification_started
    layer_result
    final_verdict
    info
  ].freeze

  belongs_to :lead

  validates :event_type,
            presence: true,
            inclusion: { in: EVENT_TYPES }
end