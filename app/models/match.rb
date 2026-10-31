# frozen_string_literal: true
# typed: true

class Match < ApplicationRecord
  has_many :notified_incidents, dependent: :destroy
  has_many :match_subscriptions, dependent: :destroy
  has_many :subscriptions, through: :match_subscriptions

  scope :upcoming, -> { where(status: "upcoming") }
  scope :live, -> { where(status: "live") }
  scope :finished, -> { where(status: "finished") }

  def live? = status == "live"
  def upcoming? = status == "upcoming"
  def finished? = status == "finished"

  # Extracts the stable id + slug from a widget API match url. Two formats:
  #   /football/match/{slug}/{id}/   (team sports — id is the last segment)
  #   /cricket/match/{slug}/         (no id — slug itself is the key)
  def self.key_for(match_hash)
    segments = match_hash["url"].to_s.split("/").reject(&:empty?)
    key = segments.last.to_s
    # No id segment (e.g. cricket urls) — same fixture repeats, so the
    # key needs the kickoff date to disambiguate.
    key += ":#{match_hash['time'].to_s[0, 10]}" if segments[-2] == "match"
    key.presence
  end

  def self.slug_for(match_hash)
    segments = match_hash["url"].to_s.split("/").reject(&:empty?)
    segments[-2] == "match" ? segments[-1] : segments[-2]
  end
end
