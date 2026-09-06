require "test_helper"

class PixelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = Account.create!(
      external_id: "acct_pixel_test",
      company_name: "Pixel Test Co",
      plan: "growth",
      monthly_credit_allowance: 1000,
      credits_used_this_cycle: 0,
      status: "active",
      enabled_modules: [
        "anura",
        "trustedform",
        "dnc"
      ]
    )

    @other_account = Account.create!(
      external_id: "acct_pixel_other",
      company_name: "Other Co",
      plan: "growth",
      monthly_credit_allowance: 1000,
      credits_used_this_cycle: 0,
      status: "active",
      enabled_modules: [
        "anura",
        "trustedform"
      ]
    )

    @admin = User.create!(
      external_id: "usr_pixel_admin",
      name: "Pixel Admin",
      email: "pixel-admin@example.com",
      role: "account_admin",
      account: @account,
      password: "password123",
      password_confirmation: "password123"
    )

    @member = User.create!(
      external_id: "usr_pixel_member",
      name: "Pixel Member",
      email: "pixel-member@example.com",
      role: "member",
      account: @account,
      password: "password123",
      password_confirmation: "password123"
    )

    @other_admin = User.create!(
      external_id: "usr_pixel_other_admin",
      name: "Other Admin",
      email: "other-pixel-admin@example.com",
      role: "account_admin",
      account: @other_account,
      password: "password123",
      password_confirmation: "password123"
    )

    @pixel = @account.pixels.create!(
      name: "Main Pixel",
      allowed_pages: [
        "http://localhost:3001"
      ],
      enabled_modules: [
        "anura",
        "trustedform"
      ],
      active: true
    )

    @other_pixel = @other_account.pixels.create!(
      name: "Other Pixel",
      allowed_pages: [],
      enabled_modules: [
        "anura"
      ],
      active: true
    )
  end

  test "authentication is required" do
    get "/pixels"

    assert_response :unauthorized
  end

  test "account admin sees only own account pixels" do
    login_as(@admin)

    get "/pixels"

    assert_response :success

    body = JSON.parse(response.body)

    ids = body["results"].map do |pixel|
      pixel["public_id"]
    end

    assert_includes ids, @pixel.public_id
    refute_includes ids, @other_pixel.public_id
  end

  test "member cannot manage pixels" do
    login_as(@member)

    get "/pixels"

    assert_response :forbidden
  end

  test "account admin cannot access another account pixel" do
    login_as(@admin)

    get "/pixels/#{@other_pixel.public_id}"

    assert_response :not_found
  end

  test "account admin can create pixel" do
    login_as(@admin)

    assert_difference("Pixel.count", 1) do
      post "/pixels",
           params: {
             pixel: {
               name: "New Pixel",
               allowed_pages: [
                 "http://localhost:3001"
               ],
               enabled_modules: [
                 "anura",
                 "trustedform"
               ],
               active: true
             }
           },
           as: :json
    end

    assert_response :created

    body = JSON.parse(response.body)

    assert_equal "New Pixel",
                 body["pixel"]["name"]

    assert body["pixel"]["public_id"].start_with?("px_")
  end

  test "cannot enable module outside account entitlement" do
    login_as(@admin)

    post "/pixels",
         params: {
           pixel: {
             name: "Invalid Pixel",
             allowed_pages: [],
             enabled_modules: [
               "anura",
               "voice"
             ],
             active: true
           }
         },
         as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)

    assert body["errors"].any? do |error|
      error.include?("voice")
    end
  end

  test "account admin can update own pixel" do
    login_as(@admin)

    patch "/pixels/#{@pixel.public_id}",
          params: {
            pixel: {
              name: "Updated Main Pixel",
              active: false,
              allowed_pages: [
                "http://localhost:3002"
              ],
              enabled_modules: [
                "anura"
              ]
            }
          },
          as: :json

    assert_response :success

    @pixel.reload

    assert_equal "Updated Main Pixel",
                 @pixel.name

    assert_equal false,
                 @pixel.active

    assert_equal ["anura"],
                 @pixel.enabled_modules
  end

  private

  def login_as(user)
    post "/login",
         params: {
           email: user.email,
           password: "password123"
         },
         as: :json

    assert_response :success
  end
end