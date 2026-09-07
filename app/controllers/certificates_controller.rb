require "openssl"
require "json"

class CertificatesController < ApplicationController
  def show
  certificate = ConsentCertificate.find_by!(
    public_id: params[:public_id]
  )

  evidence = certificate.evidence || {}

  render json: {
    certificate: {
      public_id: certificate.public_id,
      issued_at: certificate.issued_at,
      trusted_form_reference: certificate.trusted_form_reference,

      account: {
        external_id: evidence.dig("account", "external_id"),
        company_name: evidence.dig("account", "company_name")
      },

      pixel: {
        public_id: evidence.dig("pixel", "public_id"),
        name: evidence.dig("pixel", "name")
      },

      verification: evidence["verification"],

      verdict: evidence["verdict"],

      layers: public_layer_results(evidence["layers"]),

      signature: certificate.signature,
      valid: valid_signature?(certificate)
    }
  }
end

  private

  def valid_signature?(certificate)
    expected_signature =
      OpenSSL::HMAC.hexdigest(
        "SHA256",
        Rails.application.secret_key_base,
        canonical_json(certificate.evidence)
      )

    ActiveSupport::SecurityUtils.secure_compare(
      expected_signature,
      certificate.signature
    )
  end

  def canonical_json(value)
    deep_sort(value).to_json
  end

  def deep_sort(value)
    case value
    when Hash
      value
        .sort_by { |key, _| key.to_s }
        .to_h
        .transform_values { |nested| deep_sort(nested) }

    when Array
      value.map { |item| deep_sort(item) }

    else
      value
    end
  end

  def public_layer_results(layers)
  Array(layers).map do |layer|
    {
      layer_name: layer["layer_name"],
      execution_status: layer["execution_status"],
      verdict: layer["verdict"],
      risk_score: layer["risk_score"],
      reason: layer["reason"]
    }
  end
end
end