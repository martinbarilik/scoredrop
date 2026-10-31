require "test_helper"

class PollerTest < ActiveSupport::TestCase
  class FakeClient
    attr_accessor :team_payload, :match_payload

    def team(sport:, slug:, limit:)
      raise Sportscore::Error, "boom" if slug == "bad"
      raise "unexpected" if slug == "crash"
      @team_payload || { "matches" => [] }
    end

    def match(sport:, slug:)
      match_calls << slug
      if @match_payload_by_slug
        @match_payload_by_slug[slug] || { "match" => {} }
      else
        @match_payload || { "match" => {} }
      end
    end

    def match_calls = @match_calls ||= []

    attr_accessor :matches_payload, :standings_payload, :match_payload_by_slug

    def matches(sport:, limit:)
      @matches_payload || { "matches" => [] }
    end

    def standings(sport:, slug:)
      @standings_payload || { "tables" => [] }
    end
  end

  class RecordingPublisher
    attr_reader :calls

    def initialize = @calls = []

    def publish(title:, message:, tags: [])
      @calls << { title: title, message: message, tags: tags }
      true
    end
  end

  class FlakyPublisher < RecordingPublisher
    attr_accessor :fails

    def initialize = (@fails = 0; super)

    def publish(title:, message:, tags: [])
      @fails -= 1
      @fails >= 0 ? false : super
    end
  end

  FIXTURE = {
    "home" => "Barcelona", "away" => "Real Madrid",
    "home_score" => "0", "away_score" => "0",
    "status" => "upcoming", "status_text" => "Not started",
    "time" => 1.hour.from_now.iso8601,
    "competition" => "La Liga",
    "url" => "/football/match/barcelona-vs-real-madrid/abc123/"
  }.freeze

  def build(settings_attrs = {})
    client = FakeClient.new
    pub = RecordingPublisher.new
    settings = Setting.new(settings_attrs)
    poller = Poller.new(client: client, publisher: pub, settings: settings)
    [poller, client, pub]
  end

  setup do
    Subscription.create!(team_slug: "barcelona")
  end

  test "tick upserts team fixtures" do
    poller, client, = build
    client.team_payload = { "matches" => [FIXTURE] }
    poller.tick

    match = Match.find_by(key: "abc123")
    assert_equal "barcelona-vs-real-madrid", match.slug
    assert_equal "upcoming", match.status
    assert_equal "La Liga", match.competition
  end

  test "upcoming -> live sends kickoff notification once" do
    poller, client, pub = build

    client.team_payload = { "matches" => [FIXTURE] }
    poller.tick
    assert_empty pub.calls

    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }
    poller.tick
    poller.tick

    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Kickoff:") }
  end

  test "goal incident sends notification once" do
    poller, client, pub = build
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }
    client.match_payload = { "match" => {
      "home_score" => 1, "away_score" => 0,
      "incidents" => [{ "time" => 12, "type" => "Goal", "side" => "home",
                        "player" => "Lamine Yamal", "is_goal" => true,
                        "home_score" => 1, "away_score" => 0 }]
    } }

    poller.tick
    poller.tick

    goals = pub.calls.select { |c| c[:title].start_with?("Goal!") }
    assert_equal 1, goals.size
    assert_includes goals.first[:title], "1-0"
  end

  test "live -> finished sends fulltime only if tracked" do
    poller, client, pub = build

    # Match discovered already finished: no notification.
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "finished", "home_score" => "2")] }
    poller.tick
    assert_empty pub.calls

    # Now a transition we tracked: upcoming -> live -> finished.
    MatchSubscription.delete_all
    Match.delete_all
    client.team_payload = { "matches" => [FIXTURE] }
    poller.tick
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }
    poller.tick
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "finished", "home_score" => "2")] }
    poller.tick

    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Fulltime:") }
  end

  test "fulltime fires when start notifications are disabled" do
    poller, client, pub = build(notify_start: false)

    client.team_payload = { "matches" => [FIXTURE] }
    poller.tick
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }
    poller.tick
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "finished", "home_score" => "2")] }
    poller.tick

    assert_empty pub.calls.select { |c| c[:title].start_with?("Kickoff:") }
    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Fulltime:") }
  end

  test "fulltime still fires when the kickoff publish failed" do
    client = FakeClient.new
    pub = FlakyPublisher.new
    pub.fails = 1
    poller = Poller.new(client: client, publisher: pub, settings: Setting.new)

    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }
    poller.tick
    assert_nil Match.find_by!(key: "abc123").notified_started_at

    client.team_payload = { "matches" => [FIXTURE.merge("status" => "finished", "home_score" => "2")] }
    poller.tick

    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Fulltime:") }
  end

  test "publisher is rebuilt from current settings, not memoized" do
    settings = Setting.new
    poller = Poller.new(client: FakeClient.new, settings: settings)

    refute poller.send(:publisher).configured?
    settings.ntfy_url = "http://ntfy.local"
    settings.ntfy_topic = "scoredrop"
    assert poller.send(:publisher).configured?

    pub = RecordingPublisher.new
    assert_same pub, Poller.new(client: FakeClient.new, publisher: pub,
                                settings: settings).send(:publisher)
  end

  test "reminder fires when enabled and kickoff is near" do
    poller, client, pub = build(remind_minutes_before: 60)
    client.team_payload = { "matches" => [FIXTURE] }
    poller.tick
    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Starting soon:") }
  end

  test "next_interval is fast when live match exists, slow otherwise" do
    poller, client, = build
    client.team_payload = { "matches" => [FIXTURE.merge("time" => 2.days.from_now.iso8601)] }
    poller.tick
    assert_equal 900, poller.next_interval

    Match.update_all(status: "live")
    assert_equal 120, poller.next_interval

    Match.update_all(status: "upcoming", kickoff_at: 10.minutes.from_now)
    assert_equal 120, poller.next_interval
  end

  test "tick links discovered matches to their subscription" do
    poller, client, = build
    client.team_payload = { "matches" => [FIXTURE] }
    poller.tick

    sub = Subscription.find_by(team_slug: "barcelona")
    match = Match.find_by(key: "abc123")
    assert_equal [match], sub.matches.to_a
    assert_equal [sub], match.subscriptions.to_a
  end

  test "unsubscribing removes its matches but keeps shared ones" do
    Subscription.create!(team_slug: "real-madrid")
    poller, client, = build
    client.team_payload = { "matches" => [FIXTURE] } # same match for both teams
    poller.tick

    match = Match.find_by(key: "abc123")
    assert_equal 2, match.subscriptions.count

    Subscription.find_by(team_slug: "barcelona").destroy_with_matches!
    assert Match.exists?(match.id) # still tracked via real-madrid

    Subscription.find_by(team_slug: "real-madrid").destroy_with_matches!
    assert_not Match.exists?(match.id)
  end

  test "refresh syncs a single subscription immediately" do
    poller, client, = build
    client.team_payload = { "matches" => [FIXTURE] }
    poller.refresh(Subscription.find_by!(team_slug: "barcelona"))

    match = Match.find_by(key: "abc123")
    assert match
    assert_equal [match], Subscription.find_by(team_slug: "barcelona").matches.to_a
  end

  test "live feed links imminent matches the team feed missed" do
    Subscription.find_by!(team_slug: "barcelona").update!(name: "FC Barcelona")
    poller, client, = build
    client.matches_payload = { "matches" => [FIXTURE] }
    poller.tick

    match = Match.find_by(key: "abc123")
    assert_equal ["barcelona"], match.subscriptions.pluck(:team_slug)
  end

  test "old finished matches are pruned" do
    Subscription.find_by!(team_slug: "barcelona").update!(name: "FC Barcelona")
    old = Match.create!(key: "old1", slug: "x", sport: "football", home: "FC Barcelona",
                        away: "X", status: "finished", kickoff_at: 3.days.ago)
    MatchSubscription.create!(match: old, subscription: Subscription.first)
    recent = Match.create!(key: "new1", slug: "y", sport: "football", home: "FC Barcelona",
                           away: "Y", status: "finished", kickoff_at: 1.day.ago)
    MatchSubscription.create!(match: recent, subscription: Subscription.first)

    build.first.tick

    assert_not Match.exists?(old.id)
    assert Match.exists?(recent.id)
  end

  test "a bad team slug does not break the cycle" do
    Subscription.create!(team_slug: "bad")
    poller, client, = build
    client.team_payload = { "matches" => [FIXTURE] }

    assert_nothing_raised { poller.tick }
    assert Match.find_by(key: "abc123")
  end

  test "goal score diff notifies once after a silent baseline" do
    poller, client, pub = build
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }
    client.match_payload = { "match" => { "status" => "live", "home_score" => 0,
                                          "away_score" => 0, "incidents" => [] } }
    poller.tick
    assert_empty pub.calls.select { |c| c[:title].start_with?("Goal!") }

    client.match_payload = { "match" => { "status" => "live", "home_score" => 1,
                                          "away_score" => 0, "incidents" => [] } }
    poller.tick
    poller.tick

    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Goal!") }
    assert Match.find_by!(key: "abc123").notified_incidents.exists?(incident_key: "score:1:0")
  end

  test "a failed goal-diff publish is retried on the next tick" do
    client = FakeClient.new
    pub = FlakyPublisher.new
    poller = Poller.new(client: client, publisher: pub, settings: Setting.new)
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }
    client.match_payload = { "match" => { "status" => "live", "home_score" => 0,
                                          "away_score" => 0, "incidents" => [] } }
    poller.tick

    pub.fails = 1
    client.match_payload = { "match" => { "status" => "live", "home_score" => 1,
                                          "away_score" => 0, "incidents" => [] } }
    poller.tick
    poller.tick

    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Goal!") }
  end

  test "a finished match is not regressed by a stale feed status" do
    poller, client, = build
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "finished",
                                                      "home_score" => "2", "away_score" => "1")] }
    poller.tick
    assert Match.find_by!(key: "abc123").finished?

    client.team_payload = { "matches" => [FIXTURE.merge("status" => "upcoming",
                                                      "home_score" => nil, "away_score" => nil)] }
    poller.tick

    match = Match.find_by!(key: "abc123")
    assert_equal "finished", match.status
    assert_equal 2, match.home_score
    assert_equal 1, match.away_score
  end

  test "goals are suppressed when notify_goals is off" do
    poller, client, pub = build(notify_goals: false)
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }
    client.match_payload = { "match" => {
      "home_score" => 1, "away_score" => 0,
      "incidents" => [{ "time" => 12, "type" => "Goal", "side" => "home",
                        "player" => "Lamine Yamal", "is_goal" => true,
                        "home_score" => 1, "away_score" => 0 }]
    } }

    poller.tick

    assert_empty pub.calls.select { |c| c[:title].start_with?("Goal!") }
  end

  test "a failed publish is retried on the next tick" do
    client = FakeClient.new
    pub = FlakyPublisher.new
    pub.fails = 1
    poller = Poller.new(client: client, publisher: pub,
                        settings: Setting.new)
    client.team_payload = { "matches" => [FIXTURE.merge("status" => "live")] }

    poller.tick
    assert_empty pub.calls
    assert_nil Match.find_by!(key: "abc123").notified_started_at

    poller.tick
    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Kickoff:") }
    assert Match.find_by!(key: "abc123").notified_started_at
  end

  test "last_error is cleared once a clean tick runs" do
    Subscription.create!(team_slug: "bad")
    poller, client, = build
    poller.tick
    assert Poller.last_error

    Subscription.find_by(team_slug: "bad").destroy
    poller.tick
    assert_nil Poller.last_error
  ensure
    Poller.instance_variable_set(:@last_error, nil)
  end

  test "an unexpected per-team error does not break the cycle" do
    Subscription.create!(team_slug: "crash")
    poller, client, = build
    client.team_payload = { "matches" => [FIXTURE] }

    assert_nothing_raised { poller.tick }
    assert Match.find_by(key: "abc123")
    assert Poller.last_polled_at
  end

  test "opponent sweep discovers a live match missing from the feeds" do
    poller, client, pub = build
    client.team_payload = { "matches" => [
      FIXTURE.merge("url" => "/football/match/barcelona-vs-sevilla/abc123/")] }
    client.standings_payload = { "tables" => [{ "rows" => [
      { "team_slug" => "barcelona" }, { "team_slug" => "real-madrid" }] }] }
    client.match_payload_by_slug = {
      "barcelona-vs-real-madrid" => { "match" => FIXTURE.merge(
        "status" => "live", "home_score" => "1", "away_score" => "0",
        "url" => "/football/match/barcelona-vs-real-madrid/live99/",
        "time" => 30.minutes.ago.iso8601) }
    }

    poller.tick

    match = Match.find_by(key: "live99")
    assert match&.live?
    assert_equal [match], Subscription.find_by(team_slug: "barcelona").matches.where(key: "live99").to_a
    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Kickoff:") }
  end

  test "opponent sweep skips pairings with a tracked unfinished match" do
    poller, client, = build
    match = Match.create!(key: "abc123", slug: "barcelona-vs-real-madrid",
                          home: "Barcelona", away: "Real Madrid",
                          competition: "La Liga", status: "upcoming",
                          kickoff_at: 1.day.from_now)
    MatchSubscription.create!(match: match, subscription: Subscription.find_by!(team_slug: "barcelona"))
    client.standings_payload = { "tables" => [{ "rows" => [
      { "team_slug" => "barcelona" }, { "team_slug" => "real-madrid" }] }] }

    poller.tick

    assert_empty client.match_calls
  end

  test "a due match flips to live via the detail endpoint" do
    poller, client, pub = build
    # Team feed only ever reports upcoming — even past kickoff.
    client.team_payload = { "matches" => [FIXTURE.merge("time" => 10.minutes.ago.iso8601)] }
    client.match_payload = { "match" => { "status" => "live",
                                          "home_score" => "0", "away_score" => "0",
                                          "incidents" => [] } }

    poller.tick

    match = Match.find_by!(key: "abc123")
    assert match.live?
    assert_equal 1, pub.calls.count { |c| c[:title].start_with?("Kickoff:") }
  end

  test "team name and logo are cached on the subscription" do
    poller, client, = build
    client.team_payload = {
      "team" => { "name" => "FC Barcelona", "logo" => "logo.png" },
      "matches" => []
    }
    poller.tick

    sub = Subscription.find_by(team_slug: "barcelona")
    assert_equal "FC Barcelona", sub.name
    assert_equal "logo.png", sub.logo
  end
end
