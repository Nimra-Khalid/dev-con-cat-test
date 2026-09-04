class CreateVerdicts < ActiveRecord::Migration[8.1]
  def change
    create_table :verdicts do |t|
      t.references :verification_run,
                   null: false,
                   foreign_key: true,
                   index: { unique: true }

      t.string :decision,
               null: false

      t.integer :risk_score,
                null: false,
                default: 0

      t.boolean :hard_stop,
                null: false,
                default: false

      t.jsonb :reasons,
              null: false,
              default: []

      t.jsonb :policy_snapshot,
              null: false,
              default: {}

      t.datetime :decided_at,
                 null: false

      t.timestamps
    end
  end
end