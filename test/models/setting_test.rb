require "test_helper"
require "tempfile"

class SettingTest < ActiveSupport::TestCase
  test "instance creates a row with defaults" do
    s = Setting.instance
    assert s.persisted?
    assert_equal "football", s.sport
    assert_equal Setting::DEFAULT_COMPETITIONS["football"], s.competitions
    assert s.notify?(:start)
  end

  test "sport is normalized to football" do
    s = Setting.new(sport: "curling")
    assert s.valid?
    assert_equal "football", s.sport
  end

  test "competitions come from the hash or legacy array" do
    s = Setting.new(competitions: { "football" => %w[la-liga] })
    assert_equal %w[la-liga], s.competitions

    s = Setting.new(competitions: %w[serie-a]) # legacy array = football list
    assert_equal %w[serie-a], s.competitions
  end

  test "yaml import migrates settings and teams" do
    Tempfile.create("scoredrop") do |f|
      f.write(<<~YAML)
        sport: football
        teams: [fc-barcelona, real-madrid]
        remind_minutes_before: 15
        notify: {start: true, goals: false, fulltime: true}
        ntfy: {url: https://ntfy.local, topic: mytopic, token: tk1}
      YAML
      f.flush

      ENV["SCOREDROP_CONFIG"] = f.path
      Setting.delete_all
      Subscription.delete_all
      s = Setting.instance

      assert_equal "https://ntfy.local", s.ntfy_url
      assert_equal "mytopic", s.ntfy_topic
      assert_equal "tk1", s.ntfy_token
      assert_equal 15, s.remind_minutes_before
      assert_not s.notify?(:goals)
      assert_equal %w[fc-barcelona real-madrid].sort, Subscription.pluck(:team_slug).sort
    ensure
      ENV.delete("SCOREDROP_CONFIG")
    end
  end

  test "yaml import infers league from slug prefixes" do
    Tempfile.create("scoredrop") do |f|
      f.write("teams: [nhl-mtl, svk-hc-kosice, fc-barcelona]\n")
      f.flush

      ENV["SCOREDROP_CONFIG"] = f.path
      Setting.delete_all
      Subscription.delete_all
      Setting.instance

      assert_equal "nhl", Subscription.find_by(team_slug: "nhl-mtl").league
      assert_equal "extraliga", Subscription.find_by(team_slug: "svk-hc-kosice").league
      assert_equal "football", Subscription.find_by(team_slug: "fc-barcelona").league
    ensure
      ENV.delete("SCOREDROP_CONFIG")
    end
  end

  test "missing yaml file imports nothing" do
    ENV["SCOREDROP_CONFIG"] = "/nonexistent.yml"
    Setting.delete_all
    s = Setting.instance
    assert s.persisted?
    assert_nil s.ntfy_url
  ensure
    ENV.delete("SCOREDROP_CONFIG")
  end
end
