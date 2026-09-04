class CreateVerificationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :verification_runs do |t|
      t.references :lead,
                   null: false,
                   foreign_key: true

      t.string :status,
               null: false,
               default: "pending"

      t.string :policy_version,
               null: false

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :verification_runs, [:lead_id, :created_at]
  end
end