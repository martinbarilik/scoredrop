class CreateSettingsAndSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :sport, null: false, default: "football"
      t.jsonb :competitions, null: false, default: []

      t.string :ntfy_url
      t.string :ntfy_topic
      t.string :ntfy_token
      t.integer :ntfy_priority

      t.boolean :notify_start, null: false, default: true
      t.boolean :notify_goals, null: false, default: true
      t.boolean :notify_fulltime, null: false, default: true
      t.integer :remind_minutes_before, null: false, default: 0

      t.integer :poll_interval_seconds, null: false, default: 120
      t.integer :idle_poll_interval_seconds, null: false, default: 900
      t.integer :live_window_seconds, null: false, default: 1800

      t.timestamps
    end

    create_table :subscriptions do |t|
      t.string :team_slug, null: false
      t.string :name
      t.string :logo

      t.timestamps
    end

    add_index :subscriptions, :team_slug, unique: true
  end
end
