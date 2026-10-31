# frozen_string_literal: true
# typed: true

# Team discovery. The widget API has no "list teams" endpoint, but the
# standings endpoint returns team_slug for every row — so we browse teams
# by competition. For arbitrary slugs, lookup() verifies via the team
# endpoint and returns the resolved display name.
class TeamDirectory
  Team = Struct.new(:position, :name, :slug, :logo, keyword_init: true)
  Info = Struct.new(:name, :slug, :logo, keyword_init: true)

  attr_reader :last_competition_name

  def initialize(client: Sportscore::Client.new)
    @client = client
  end

  # Returns [Team]; raises Sportscore::Error on API failure.
  # Sets last_competition_name to the API's display name for the competition.
  def teams(competition_slug, sport: "football")
    data = @client.standings(sport: sport, slug: competition_slug)
    raise Sportscore::Error, data["error"] if data["error"]

    @last_competition_name = data["competition"]
    Array(data["tables"]).flat_map { |t| Array(t["rows"]) }.map do |row|
      Team.new(position: row["pos"], name: row["team"],
               slug: row["team_slug"], logo: row["team_logo"])
    end
  end

  # Verify a slug via the team endpoint. Returns Info or nil when unknown.
  def lookup(slug, sport: "football")
    data = @client.team(sport: sport, slug: slug, limit: 1)
    team = data["team"]
    return nil unless team.is_a?(Hash) && team["name"].present?

    Info.new(name: team["name"], slug: team["slug"] || slug, logo: team["logo"])
  rescue Sportscore::Error
    nil
  end
end
