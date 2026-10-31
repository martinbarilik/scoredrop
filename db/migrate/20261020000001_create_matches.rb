class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.string :key, null: false
      t.string :slug, null: false
      t.string :sport, null: false, default: "football"
      t.string :home, null: false
      t.string :away, null: false
      t.string :competition
      t.datetime :kickoff_at
      t.string :status, null: false
      t.integer :home_score
      t.integer :away_score
      t.datetime :notified_reminded_at
      t.datetime :notified_started_at
      t.datetime :notified_finished_at

      t.timestamps
    end

    add_index :matches, :key, unique: true
    add_index :matches, :status
  end
end
