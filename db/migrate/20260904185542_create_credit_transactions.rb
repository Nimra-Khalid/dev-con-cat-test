class CreateCreditTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_transactions do |t|
      t.references :account,
                   null: false,
                   foreign_key: true

      t.references :verification_run,
                   null: false,
                   foreign_key: true

      t.string :layer_name,
               null: false

      t.integer :amount,
                null: false

      t.string :transaction_type,
               null: false,
               default: "verification"

      t.timestamps
    end

    add_index :credit_transactions,
              [:verification_run_id, :layer_name],
              unique: true
  end
end