require "test_helper"

class MatchTest < ActiveSupport::TestCase
  test "key_for and slug_for parse the widget api url" do
    payload = { "url" => "/football/match/barcelona-vs-cobreloa/23xmvkh807znqg8/" }
    assert_equal "23xmvkh807znqg8", Match.key_for(payload)
    assert_equal "barcelona-vs-cobreloa", Match.slug_for(payload)
  end

  test "key_for disambiguates id-less urls by kickoff date" do
    m1 = { "url" => "/cricket/match/zimbabwe-vs-afghanistan/", "time" => "2026-10-23T11:30:00+00:00" }
    m2 = { "url" => "/cricket/match/zimbabwe-vs-afghanistan/", "time" => "2026-10-19T11:30:00+00:00" }
    assert_not_equal Match.key_for(m1), Match.key_for(m2)
    assert_equal "zimbabwe-vs-afghanistan", Match.slug_for(m1)
  end

  test "key_for returns nil for missing urls" do
    assert_nil Match.key_for({ "url" => nil })
    assert_nil Match.key_for({})
  end

  test "status predicates" do
    assert Match.new(status: "live").live?
    assert Match.new(status: "upcoming").upcoming?
    assert Match.new(status: "finished").finished?
  end
end
