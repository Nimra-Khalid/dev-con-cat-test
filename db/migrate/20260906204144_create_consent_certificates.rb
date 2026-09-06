class CreateConsentCertificates < ActiveRecord::Migration[8.1]
  def change
    create_table :consent_certificates do |t|
      t.references :verification_run,
                   null: false,
                   foreign_key: true,
                   index: { unique: true }

      t.string :public_id, null: false
      t.string :trusted_form_reference

      # Snapshot of exactly what supported the decision.
      t.jsonb :evidence, null: false, default: {}

      # HMAC signature used to detect evidence tampering.
      t.string :signature, null: false

      t.datetime :issued_at, null: false

      t.timestamps
    end

    add_index :consent_certificates, :public_id, unique: true
  end
end