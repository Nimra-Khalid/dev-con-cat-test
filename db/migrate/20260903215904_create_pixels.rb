class CreatePixels < ActiveRecord::Migration[8.1]
  def change
    create_table :pixels do |t|
      t.string :public_id, null: false
      t.string :name, null: false

      t.references :account,
                   null: false,
                   foreign_key: true

      t.jsonb :allowed_pages,
              null: false,
              default: []

      t.jsonb :enabled_modules,
              null: false,
              default: []

      t.boolean :active,
                null: false,
                default: true

      t.timestamps
    end

    add_index :pixels, :public_id, unique: true
  end
end