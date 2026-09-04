class CreateLayerResults < ActiveRecord::Migration[8.1]
  def change
    create_table :layer_results do |t|
      t.references :verification_run,
                   null: false,
                   foreign_key: true

      t.string :layer_name,
               null: false

      t.string :execution_status,
               null: false,
               default: "pending"

      t.string :verdict

      t.integer :risk_score,
                null: false,
                default: 0

      t.text :reason

      t.jsonb :raw_response,
              null: false,
              default: {}

      t.integer :credit_cost,
                null: false,
                default: 0

      t.timestamps
    end

    add_index :layer_results,
              [:verification_run_id, :layer_name],
              unique: true
  end
end