class VerificationJob < ApplicationJob
  queue_as :default

  def perform(lead_id)
    lead = Lead.find(lead_id)

    VerificationRunner.new(lead).call
  end
end