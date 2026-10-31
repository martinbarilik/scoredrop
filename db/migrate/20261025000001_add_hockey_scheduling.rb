class AddHockeyScheduling < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :league, :string, default: 'football', null: false
    add_column :subscriptions, :schedule_checked_at, :datetime
    add_column :matches, :event_date, :date
    add_column :matches, :result_checked_at, :datetime
    add_column :matches, :schedule_tracked_at, :datetime
    create_table :feed_caches do |t|
      t.string :key, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :fetched_at, null: false
      t.index :key, unique: true
    end
  end
end
