class AddFixtureKeyToLeads < ActiveRecord::Migration[8.1]
  def change
    add_column :leads, :fixture_key, :string
    add_index :leads, :fixture_key
  end
end