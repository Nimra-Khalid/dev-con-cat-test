class LeadsController < ApplicationController
  before_action :authenticate_user!

  DEFAULT_PAGE_SIZE = 20
  MAX_PAGE_SIZE = 100

  def index
    leads = accessible_leads
      .includes(
        pixel_session: :pixel,
        verification_runs: [:verdict, :layer_results]
      )

    leads = apply_search(leads)
    leads = apply_verdict_filter(leads)

    leads = leads.order(created_at: :desc)

    page = normalized_page
    per_page = normalized_per_page

    total_count = leads.count

    paginated_leads = leads
      .offset((page - 1) * per_page)
      .limit(per_page)

    render json: {
      results: paginated_leads.map { |lead| serialize_lead(lead) },
      meta: {
        page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count.to_f / per_page).ceil
      }
    }
  end

  def show
    lead = accessible_leads
      .includes(
        :activity_events,
        pixel_session: :pixel,
        verification_runs: [
          :verdict,
          :layer_results,
          :consent_certificate
        ]
      )
      .find_by!(external_id: params[:id])

    render json: serialize_lead(
      lead,
      detailed: true
    )
  end

  private

  def apply_search(relation)
    return relation unless params[:search].present?

    search = "%#{params[:search].strip}%"

    relation.where(
      <<~SQL.squish,
        leads.external_id ILIKE :search OR
        leads.first_name ILIKE :search OR
        leads.last_name ILIKE :search OR
        leads.email ILIKE :search OR
        leads.phone ILIKE :search OR
        leads.campaign ILIKE :search
      SQL
      search: search
    )
  end

  def apply_verdict_filter(relation)
    return relation unless params[:verdict].present?

    decision = params[:verdict].to_s.upcase

    return relation unless Verdict::DECISIONS.include?(decision)

    relation
      .joins(verification_runs: :verdict)
      .where(verdicts: { decision: decision })
      .distinct
  end

  def normalized_page
    page = params[:page].to_i
    page.positive? ? page : 1
  end

  def normalized_per_page
    requested = params[:per_page].to_i

    return DEFAULT_PAGE_SIZE unless requested.positive?

    [requested, MAX_PAGE_SIZE].min
  end

  def serialize_lead(lead, detailed: false)
    run = lead.verification_runs
      .max_by(&:created_at)

    verdict = run&.verdict
    certificate = run&.consent_certificate

    data = {
      id: lead.external_id,

      person: {
        first_name: lead.first_name,
        last_name: lead.last_name,
        email: lead.email,
        phone: lead.phone
      },

      campaign: lead.campaign,

      submitted_at: lead.submitted_at,

      landing_page_url: lead.landing_page_url,

      pixel: {
        public_id: lead.pixel.public_id,
        name: lead.pixel.name
      },

      verification: {
        status: run&.status,
        policy_version: run&.policy_version,
        started_at: run&.started_at,
        completed_at: run&.completed_at
      },

      verdict: verdict && {
        decision: verdict.decision,
        risk_score: verdict.risk_score,
        hard_stop: verdict.hard_stop,
        reasons: verdict.reasons,
        decided_at: verdict.decided_at
      },

      certificate: certificate && {
        public_id: certificate.public_id,
        issued_at: certificate.issued_at,
        valid_url: "/certificates/#{certificate.public_id}"
      }
    }

    if detailed
      data[:layers] =
        if run
          run.layer_results.order(:id).map do |layer|
            {
              layer_name: layer.layer_name,
              execution_status: layer.execution_status,
              verdict: layer.verdict,
              risk_score: layer.risk_score,
              reason: layer.reason,
              credit_cost: layer.credit_cost,
              raw_response: layer.raw_response
            }
          end
        else
          []
        end

      data[:activity] =
        lead.activity_events
          .order(:id)
          .map do |event|
            {
              id: event.id,
              event_type: event.event_type,
              payload: event.payload,
              created_at: event.created_at
            }
          end
    end

    data
  end
end