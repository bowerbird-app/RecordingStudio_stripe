class CreatePressKits < ActiveRecord::Migration[8.1]
  def change
    create_table :press_kits, id: :uuid do |t|
      t.string :name

      t.timestamps
    end
  end
end
