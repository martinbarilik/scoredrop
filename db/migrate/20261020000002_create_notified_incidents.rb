class CreateNotifiedIncidents < ActiveRecord::Migration[8.1]
  def change
    create_table :notified_incidents do |t|
      t.references :match, null: false, foreign_key: true
      t.string :incident_key, null: false

      t.timestamps
    end

    add_index :notified_incidents, %i[match_id incident_key], unique: true
  end
end
