require "openssl"
require "json"

class CertificatesController < ApplicationController
  def show
    certificate = ConsentCertificate.find_by!(
      public_id: params[:public_id]
    )

    render json: {
      certificate: {
        public_id: certificate.public_id,
        issued_at: certificate.issued_at,
        trusted_form_reference: certificate.trusted_form_reference,
        evidence: certificate.evidence,
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
end