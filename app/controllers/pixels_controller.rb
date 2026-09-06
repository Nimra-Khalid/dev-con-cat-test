class PixelsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_pixel_management!
  before_action :set_pixel, only: [:show, :update]

  def index
    pixels = accessible_pixels.order(created_at: :desc)

    render json: {
      results: pixels.map { |pixel| serialize_pixel(pixel) },
      available_modules: current_user.account.enabled_modules
    }
  end

  def show
    render json: serialize_pixel(@pixel)
  end

  def create
    account = current_user.account

    pixel = account.pixels.new(pixel_params)

    if pixel.save
      render json: {
        pixel: serialize_pixel(pixel),
        snippet: snippet_for(pixel)
      }, status: :created
    else
      render json: {
        errors: pixel.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @pixel.update(pixel_params)
      render json: {
        pixel: serialize_pixel(@pixel),
        snippet: snippet_for(@pixel)
      }, status: :ok
    else
      render json: {
        errors: @pixel.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def accessible_pixels
    current_user.account.pixels
  end

  def set_pixel
    @pixel = accessible_pixels.find_by!(
      public_id: params[:id]
    )
  end

  def authorize_pixel_management!
    return if current_user.account_admin?

    render json: {
      error: "You are not authorized to manage pixels"
    }, status: :forbidden
  end

  def pixel_params
    params.require(:pixel).permit(
      :name,
      :active,
      allowed_pages: [],
      enabled_modules: []
    )
  end

  def serialize_pixel(pixel)
    {
      public_id: pixel.public_id,
      name: pixel.name,
      active: pixel.active,
      allowed_pages: pixel.allowed_pages,
      enabled_modules: pixel.enabled_modules,
      available_modules: pixel.account.enabled_modules,
      created_at: pixel.created_at,
      updated_at: pixel.updated_at
    }
  end

  def snippet_for(pixel)
    <<~HTML.strip
      <script
        src="/examples/super-pixel.js"
        data-pixel-id="#{pixel.public_id}"
        data-endpoint="#{request.base_url}">
      </script>
    HTML
  end
end