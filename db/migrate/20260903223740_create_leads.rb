class CreateLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :leads do |t|
      t.string :external_id, null: false

      t.references :pixel_session,
             null: false,
             foreign_key: true,
             index: { unique: true }

      t.string :first_name
      t.string :last_name
      t.string :email
      t.string :phone

      t.string :campaign
      t.text :landing_page_url, null: false

      t.string :submit_ip
      t.text :user_agent

      t.text :trusted_form_cert_url

      t.integer :form_dwell_ms
      t.datetime :submitted_at, null: false

      t.timestamps
    end

    add_index :leads, :external_id, unique: true
   end
end