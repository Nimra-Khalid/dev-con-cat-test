class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :external_id, null: false
      t.string :company_name, null: false
      t.string :plan, null: false

      t.integer :monthly_credit_allowance, null: false, default: 0
      t.integer :credits_used_this_cycle, null: false, default: 0

      t.date :cycle_start
      t.date :cycle_end

      t.string :status, null: false, default: "active"

      t.jsonb :enabled_modules, null: false, default: []

      t.integer :avg_daily_burn, null: false, default: 0

      t.string :billing_contact

      t.timestamps
    end

    add_index :accounts, :external_id, unique: true
  end
end