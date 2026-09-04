class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_events do |t|
      t.references :lead,
                   null: false,
                   foreign_key: true

      t.string :event_type,
               null: false

      t.jsonb :payload,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :activity_events,
              [:lead_id, :id]
  end
end