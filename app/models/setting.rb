# frozen_string_literal: true
# typed: true

require "yaml"

# Single-row application settings (source of truth for ntfy, notify
# toggles, polling intervals, sport, browsable competitions).
# On very first access, values are imported from config/scoredrop.yml
# (or SCOREDROP_CONFIG) if present — one-time migration, then the file
# is ignored.
class Setting < ApplicationRecord
  SPORTS = %w[football].freeze # other sports' API data is too thin to be useful

  validates :sport, inclusion: { in: SPORTS }
  before_validation ->(setting) { setting.sport = SPORTS.first }

  DEFAULT_COMPETITIONS = {
    "football" => %w[
      spanish-la-liga
      english-premier-league
      bundesliga
      italian-serie-a
      french-ligue-1
      uefa-champions-league
      uefa-europa-league
      netherlands-eredivisie
      turkish-super-league
      scottish-premiership
      brazilian-serie-a
    ]
  }.freeze

  def self.instance
    record = first || create!(id: 1)
    record.import_from_yaml if record.previously_new_record?
    record
  rescue ActiveRecord::RecordNotUnique
    # Concurrent first-boot create lost the race for id 1 — use the winner.
    first
  end

  # Competitions list for the Browse page, scoped to the active sport.
  def competitions = competitions_for(sport)

  # `competitions` is stored as {sport => [slugs]}; legacy plain arrays are
  # treated as the football list.
  def competitions_for(sport)
    raw = self[:competitions]
    list = if raw.is_a?(Hash)
             raw[sport]
           elsif sport == "football"
             raw
           end
    list.presence || DEFAULT_COMPETITIONS.fetch(sport, [])
  end

  def config_path
    ENV["SCOREDROP_CONFIG"] || Rails.root.join("config/scoredrop.yml").to_s
  end

  # One-time YAML import: settings + team subscriptions.
  def import_from_yaml
    data = YAML.safe_load(File.read(config_path), permitted_classes: [Symbol], aliases: true)
    return unless data.is_a?(Hash)

    data = data.deep_stringify_keys
    ntfy = data["ntfy"] || {}
    notify = data["notify"] || {}

    update!(
      sport: data["sport"].presence || sport,
      competitions: data["competitions"].presence || {},
      ntfy_url: ntfy["url"],
      ntfy_topic: ntfy["topic"],
      ntfy_token: ntfy["token"],
      ntfy_priority: ntfy["priority"],
      notify_start: notify.fetch("start", notify_start),
      notify_goals: notify.fetch("goals", notify_goals),
      notify_fulltime: notify.fetch("fulltime", notify_fulltime),
      remind_minutes_before: data["remind_minutes_before"] || remind_minutes_before,
      poll_interval_seconds: data["poll_interval_seconds"] || poll_interval_seconds,
      idle_poll_interval_seconds: data["idle_poll_interval_seconds"] || idle_poll_interval_seconds,
      live_window_seconds: data["live_window_seconds"] || live_window_seconds
    )

    Array(data["teams"]).each do |slug|
      slug = slug.to_s.strip
      league = case slug
               when /\Anhl-/ then "nhl"
               when /\Asvk-/ then "extraliga"
               else "football"
               end
      sub = Subscription.find_or_create_by(team_slug: slug, league: league)
      Rails.logger.warn("[settings] skipped invalid team slug: #{slug}") unless sub.persisted?
    end
    Rails.logger.info("[settings] imported config from #{config_path}")
  rescue Psych::SyntaxError, Errno::ENOENT, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[settings] yaml import skipped: #{e.message}")
  end

  def notify?(event) = public_send("notify_#{event}")

  def poll_interval = poll_interval_seconds.clamp(30, 86_400)
  def idle_poll_interval = idle_poll_interval_seconds.clamp(60, 86_400)
  def live_window = live_window_seconds.clamp(0, 86_400)

  def ntfy_configured? = ntfy_url.present? && ntfy_topic.present?
end
