# frozen_string_literal: true
# typed: true

class Subscription < ApplicationRecord
  has_many :match_subscriptions, dependent: :destroy
  has_many :matches, through: :match_subscriptions

  validates :team_slug, presence: true, uniqueness: true,
                        format: { with: /\A[a-z0-9-]+\z/ }

  LEAGUES = { 'football' => 'Football', 'nhl' => 'NHL', 'extraliga' => 'Slovak Extraliga' }.freeze
  HOCKEY_LEAGUES = %w[nhl extraliga].freeze

  validates :league, inclusion: { in: LEAGUES.keys }
  validates :team_slug, format: { with: /\Anhl-[a-z]{3}\z/ }, if: ->(sub) { sub.league == 'nhl' }
  validates :team_slug, format: { with: /\Asvk-[a-z0-9-]+\z/ }, if: ->(sub) { sub.league == 'extraliga' }

  scope :ordered, -> { order(:team_slug) }

  # Destroys the subscription plus every match tracked only via it — a match
  # shared with another subscribed team (e.g. El Clásico when following both)
  # is kept.
  def destroy_with_matches!
    transaction do
      match_subscriptions.includes(:match).find_each do |link|
        match = link.match
        link.destroy!
        match&.destroy! if match&.match_subscriptions&.reload&.none?
      end
      destroy!
    end
  end
end
