class CreditManager
  MODULE_COSTS = {
    "anura" => 2,
    "trustedform" => 1,
    "dnc" => 1,
    "blacklist_alliance" => 2,
    "phone_validation" => 3,
    "email_validation" => 2,
    "vpn_proxy" => 1,
    "enrichment" => 4,
    "duplicate_detection" => 1,
    "voice" => 5
  }.freeze

  def initialize(account, verification_run)
    @account = account
    @verification_run = verification_run
  end

  def charge!(layer_name)
    cost = cost_for(layer_name)

    return true if cost.zero?

    account.with_lock do
      return false if account.credits_remaining < cost

      CreditTransaction.create!(
        account: account,
        verification_run: verification_run,
        layer_name: layer_name,
        amount: cost
      )

      account.increment!(
        :credits_used_this_cycle,
        cost
      )
    end

    true
  end

  def cost_for(layer_name)
    MODULE_COSTS.fetch(layer_name, 0)
  end

  private

  attr_reader :account, :verification_run
end