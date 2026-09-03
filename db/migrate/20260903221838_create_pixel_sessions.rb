class CreatePixelSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :pixel_sessions do |t|
      t.string :session_id, null: false

      t.references :pixel,
                   null: false,
                   foreign_key: true

      t.text :page_url, null: false
      t.text :referrer
      t.text :user_agent
      t.string :visit_ip
      t.datetime :started_at, null: false

      t.timestamps
    end

    add_index :pixel_sessions, :session_id, unique: true
  end
end