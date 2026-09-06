puts "Seeding Super Pixel demo data..."

# ------------------------------------------------------------
# Accounts
# ------------------------------------------------------------

solarpro = Account.find_or_initialize_by(
  external_id: "acct_solarpro"
)

solarpro.update!(
  company_name: "SolarPro",
  plan: "growth",
  monthly_credit_allowance: 25_000,
  credits_used_this_cycle: 21_840,
  status: "active",
  avg_daily_burn: 1_140,
  enabled_modules: [
    "anura",
    "trustedform",
    "dnc",
    "blacklist_alliance",
    "phone_validation",
    "email_validation",
    "vpn_proxy",
    "enrichment",
    "duplicate_detection"
  ]
)

medicare = Account.find_or_initialize_by(
  external_id: "acct_medicareedge"
)

medicare.update!(
  company_name: "Medicare Edge",
  plan: "enterprise",
  monthly_credit_allowance: 120_000,
  credits_used_this_cycle: 47_210,
  status: "active",
  avg_daily_burn: 2_480,
  enabled_modules: [
    "anura",
    "trustedform",
    "dnc",
    "blacklist_alliance",
    "phone_validation",
    "email_validation",
    "enrichment",
    "duplicate_detection",
    "voice"
  ]
)

autoinsure = Account.find_or_initialize_by(
  external_id: "acct_autoinsure"
)

autoinsure.update!(
  company_name: "AutoInsure",
  plan: "starter",
  monthly_credit_allowance: 8_000,
  credits_used_this_cycle: 7_920,
  status: "past_due",
  avg_daily_burn: 410,
  enabled_modules: [
    "anura",
    "trustedform",
    "dnc",
    "phone_validation",
    "duplicate_detection"
  ]
)

super_admin =
  User.find_or_initialize_by(
    email: "admin@superpixel.test"
  )

super_admin.assign_attributes(
  external_id: "usr_super_admin",
  name: "Platform Admin",
  role: "super_admin",
  account: nil,
  password: "password123",
  password_confirmation: "password123"
)

super_admin.save!

solar_admin =
  User.find_or_initialize_by(
    email: "admin@solarpro.test"
  )

solar_admin.assign_attributes(
  external_id: "usr_solar_admin",
  name: "SolarPro Admin",
  role: "account_admin",
  account: solarpro,
  password: "password123",
  password_confirmation: "password123"
)

solar_admin.save!

solar_member =
  User.find_or_initialize_by(
    email: "member@solarpro.test"
  )

solar_member.assign_attributes(
  external_id: "usr_solar_member",
  name: "SolarPro Member",
  role: "member",
  account: solarpro,
  password: "password123",
  password_confirmation: "password123"
)

solar_member.save!

# ------------------------------------------------------------
# Demo Pixel
# ------------------------------------------------------------
#
# This public_id intentionally matches examples/landing-page.html.
#
# Account.enabled_modules = what the subscription allows.
# Pixel.enabled_modules   = what this specific pixel actually runs.
#
# The Pixel model already ensures this list is a subset of the
# owning account's enabled modules.
# ------------------------------------------------------------

demo_pixel = Pixel.find_or_initialize_by(
  public_id: "px_9f2a01"
)

demo_pixel.assign_attributes(
  account: solarpro,
  name: "Solar Savings Demo Pixel",

  # Blank means allow any landing page during local demo.
  #
  # This avoids localhost/file:// differences while developing.
  # A production pixel should use explicit approved domains/pages.
  allowed_pages: [],

  enabled_modules: solarpro.enabled_modules,

  active: true
)

demo_pixel.save!

puts
puts "Seed complete."
puts "--------------------------------------------------"
puts "Accounts:"
puts "  #{solarpro.company_name} (#{solarpro.external_id})"
puts "  #{medicare.company_name} (#{medicare.external_id})"
puts "  #{autoinsure.company_name} (#{autoinsure.external_id})"
puts
puts "Demo Pixel:"
puts "  public_id: #{demo_pixel.public_id}"
puts "  account:   #{demo_pixel.account.company_name}"
puts
puts "SolarPro credits remaining:"
puts "  #{solarpro.credits_remaining}"
puts "--------------------------------------------------"

puts "Demo Login Users:"
puts "  Super Admin:"
puts "    admin@superpixel.test / password123"
puts
puts "  SolarPro Account Admin:"
puts "    admin@solarpro.test / password123"
puts
puts "  SolarPro Member:"
puts "    member@solarpro.test / password123"
puts "--------------------------------------------------"
