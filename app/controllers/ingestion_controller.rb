require "uri"
class IngestionController < ApplicationController
  skip_before_action :verify_authenticity_token

  def visit
    pixel = Pixel.find_by(
      public_id: params[:pixel_id]
    )

    unless pixel
      return render json: {
        error: "Invalid pixel"
      }, status: :not_found
    end

    unless pixel.active
      return render json: {
        error: "Pixel is inactive"
      }, status: :unprocessable_entity
    end

    unless page_allowed?(pixel, params[:page_url])
      return render json: {
        error: "Landing page is not allowed for this pixel"
      }, status: :forbidden
    end

    session =
      pixel.pixel_sessions.find_or_initialize_by(
        session_id: params[:session_id]
      )

    session.assign_attributes(
      page_url: params[:page_url],
      referrer: params[:referrer],
      user_agent: params[:user_agent],
      visit_ip: request.remote_ip,
      started_at:
        parse_time(params[:started_at]) || Time.current
    )

    session.save!

    render json: {
      session_id: session.session_id,
      pixel_id: pixel.public_id,
      status: "ok"
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      error: e.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def create_lead
    pixel = Pixel.find_by(
      public_id: params[:pixel_id]
    )

    unless pixel
      return render json: {
        error: "Invalid pixel"
      }, status: :not_found
    end

    unless pixel.active
      return render json: {
        error: "Pixel is inactive"
      }, status: :unprocessable_entity
    end

    session =
      pixel.pixel_sessions.find_by(
        session_id: params[:session_id]
      )

    unless session
      return render json: {
        error: "Pixel session not found"
      }, status: :not_found
    end

    unless page_allowed?(pixel, session.page_url)
      return render json: {
       error: "Landing page is not allowed for this pixel"
      }, status: :forbidden
    end

    lead =
      session.build_lead(
        external_id:
          params[:lead_id].presence ||
          generate_lead_id,

        fixture_key: params[:fixture_key],

        first_name:
          field_value("first_name"),

        last_name:
          field_value("last_name"),

        email:
          field_value("email"),

        phone:
          field_value("phone"),

        campaign:
          params[:campaign],

        landing_page_url:
          session.page_url,

        submit_ip:
          request.remote_ip,

        user_agent:
          request.user_agent,

        trusted_form_cert_url:
          params[:trusted_form_cert_url],

        form_dwell_ms:
          params[:form_dwell_ms],

        submitted_at:
          parse_time(params[:submitted_at]) ||
          Time.current
      )

    lead.save!

  VerificationJob.perform_later(lead.id)

  render json: {
    lead_id: lead.external_id,
    status: "verification_queued"
  }, status: :accepted

  rescue ActiveRecord::RecordInvalid => e
    render json: {
      error: e.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def activity
  lead = Lead.find_by(
    external_id: params[:lead_id]
  )

  unless lead
    return render json: {
      error: "Lead not found"
    }, status: :not_found
  end

  events =
    lead
      .activity_events
      .order(:id)

  if params[:after_id].present?
    events =
      events.where(
        "id > ?",
        params[:after_id].to_i
      )
  end

  render json: {
    lead_id: lead.external_id,
    events: events.map do |event|
      {
        id: event.id,
        event_type: event.event_type,
        payload: event.payload,
        created_at: event.created_at
      }
    end
  }
end

  private

  def field_value(field_name)
    fields = params[:fields]

    return nil unless fields

    if fields.respond_to?(:[])
      fields[field_name] ||
        fields[field_name.to_sym]
    end
  end

  def generate_lead_id
    "LEAD-#{SecureRandom.hex(6).upcase}"
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

def page_allowed?(pixel, page_url)
  return true if pixel.allowed_pages.blank?
  return false if page_url.blank?

  incoming_uri = parse_uri(page_url)
  return false unless incoming_uri

  pixel.allowed_pages.any? do |allowed_page|
    allowed_uri = parse_uri(allowed_page)

    next false unless allowed_uri

    same_origin =
      normalized_origin(allowed_uri) ==
      normalized_origin(incoming_uri)

    next false unless same_origin

    allowed_path =
      normalize_path(allowed_uri.path)

    incoming_path =
      normalize_path(incoming_uri.path)

    # If only the site origin is configured,
    # allow any path on that same origin.
    if allowed_path == "/"
      true
    else
      allowed_path == incoming_path
    end
  end
end

def parse_uri(url)
  uri = URI.parse(url.to_s)

  return nil unless %w[http https].include?(
    uri.scheme&.downcase
  )

  return nil if uri.host.blank?

  uri
rescue URI::InvalidURIError
  nil
end

def normalized_origin(uri)
  "#{uri.scheme.downcase}://" \
    "#{uri.host.downcase}" \
    "#{normalized_port(uri)}"
end

def normalize_path(path)
  normalized = path.presence || "/"

  normalized = normalized.chomp("/")

  normalized.presence || "/"
end

def normalized_port(uri)
  default_port =
    (uri.scheme.downcase == "https" &&
      uri.port == 443) ||
    (uri.scheme.downcase == "http" &&
      uri.port == 80)

  default_port ? "" : ":#{uri.port}"
end

def normalized_port(uri)
  return "" unless uri.port

  default_port =
    (uri.scheme == "https" && uri.port == 443) ||
    (uri.scheme == "http" && uri.port == 80)

  default_port ? "" : ":#{uri.port}"
end
end