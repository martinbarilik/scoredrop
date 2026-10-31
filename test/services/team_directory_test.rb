require "test_helper"

class TeamDirectoryTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(payloads = {}) = @payloads = payloads
    def standings(sport:, slug:) = @payloads.fetch(slug, { "error" => "Competition not found" })
    def team(sport:, slug:, limit:) = @payloads.fetch("team:#{slug}", { "error" => "not found" })
  end

  STANDINGS = {
    "tables" => [{ "rows" => [
      { "pos" => 1, "team" => "FC Barcelona", "team_slug" => "fc-barcelona", "team_logo" => "l1" },
      { "pos" => 2, "team" => "Real Madrid", "team_slug" => "real-madrid", "team_logo" => "l2" }
    ] }]
  }.freeze

  test "teams returns rows with slugs" do
    dir = TeamDirectory.new(client: FakeClient.new("la-liga" => STANDINGS))
    teams = dir.teams("la-liga")
    assert_equal 2, teams.size
    assert_equal "fc-barcelona", teams.first.slug
  end

  test "teams raises on api error payloads" do
    dir = TeamDirectory.new(client: FakeClient.new)
    assert_raises(Sportscore::Error) { dir.teams("nope") }
  end

  test "lookup resolves name for valid slug, nil for invalid" do
    dir = TeamDirectory.new(client: FakeClient.new(
      "team:fc-barcelona" => { "team" => { "name" => "FC Barcelona", "slug" => "fc-barcelona" } }))
    assert_equal "FC Barcelona", dir.lookup("fc-barcelona").name
    assert_nil dir.lookup("not-a-team")
  end
end
