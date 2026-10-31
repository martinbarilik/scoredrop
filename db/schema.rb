# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_25_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "feed_caches", force: :cascade do |t|
    t.string "key", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "fetched_at", null: false
    t.index ["key"], name: "index_feed_caches_on_key", unique: true
  end

  create_table "match_subscriptions", force: :cascade do |t|
    t.bigint "match_id", null: false
    t.bigint "subscription_id", null: false
    t.index ["match_id", "subscription_id"], name: "idx_match_subs_uniq", unique: true
    t.index ["match_id"], name: "index_match_subscriptions_on_match_id"
    t.index ["subscription_id"], name: "index_match_subscriptions_on_subscription_id"
  end

  create_table "matches", force: :cascade do |t|
    t.string "key", null: false
    t.string "slug", null: false
    t.string "sport", default: "football", null: false
    t.string "home", null: false
    t.string "away", null: false
    t.string "competition"
    t.datetime "kickoff_at"
    t.string "status", null: false
    t.integer "home_score"
    t.integer "away_score"
    t.datetime "notified_reminded_at"
    t.datetime "notified_started_at"
    t.datetime "notified_finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "event_date"
    t.datetime "result_checked_at"
    t.datetime "schedule_tracked_at"
    t.index ["key"], name: "index_matches_on_key", unique: true
    t.index ["status"], name: "index_matches_on_status"
  end

  create_table "notified_incidents", force: :cascade do |t|
    t.bigint "match_id", null: false
    t.string "incident_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["match_id", "incident_key"], name: "index_notified_incidents_on_match_id_and_incident_key", unique: true
    t.index ["match_id"], name: "index_notified_incidents_on_match_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "sport", default: "football", null: false
    t.jsonb "competitions", default: [], null: false
    t.string "ntfy_url"
    t.string "ntfy_topic"
    t.string "ntfy_token"
    t.integer "ntfy_priority"
    t.boolean "notify_start", default: true, null: false
    t.boolean "notify_goals", default: true, null: false
    t.boolean "notify_fulltime", default: true, null: false
    t.integer "remind_minutes_before", default: 0, null: false
    t.integer "poll_interval_seconds", default: 120, null: false
    t.integer "idle_poll_interval_seconds", default: 900, null: false
    t.integer "live_window_seconds", default: 1800, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "subscriptions", force: :cascade do |t|
    t.string "team_slug", null: false
    t.string "name"
    t.string "logo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "league", default: "football", null: false
    t.datetime "schedule_checked_at"
    t.index ["team_slug"], name: "index_subscriptions_on_team_slug", unique: true
  end

  add_foreign_key "match_subscriptions", "matches"
  add_foreign_key "match_subscriptions", "subscriptions"
  add_foreign_key "notified_incidents", "matches"
end
