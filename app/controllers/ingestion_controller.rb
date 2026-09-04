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

    lead =
      session.build_lead(
        external_id:
          params[:lead_id].presence ||
          generate_lead_id,

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

    verdict =
      VerificationRunner
        .new(lead)
        .call

    render json: {
      lead_id: lead.external_id,
      verification_run_id:
        verdict.verification_run_id,
      verdict: verdict.decision,
      risk_score: verdict.risk_score,
      hard_stop: verdict.hard_stop,
      reasons: verdict.reasons
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      error: e.record.errors.full_messages
    }, status: :unprocessable_entity
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

    pixel.allowed_pages.any? do |allowed_page|
      page_url.to_s.start_with?(
        allowed_page.to_s
      )
    end
  end
end