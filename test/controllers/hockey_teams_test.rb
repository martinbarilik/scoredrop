require 'test_helper'

class HockeyTeamsTest < ActionDispatch::IntegrationTest
  setup do
    FeedCache.create!(key: 'nhl:teams', fetched_at: Time.current, payload: {
      'standings' => [
        { 'teamName' => { 'default' => 'Montréal Canadiens' }, 'teamAbbrev' => { 'default' => 'MTL' } },
        { 'teamName' => { 'default' => 'Boston Bruins' }, 'teamAbbrev' => { 'default' => 'BOS' } }
      ]
    })
    FeedCache.create!(key: 'nhl:schedule:nhl-bos', fetched_at: Time.current, payload: { 'games' => [] })
  end

  test 'browse all NHL teams and subscribe without football API requests' do
    get teams_path(league: 'nhl')
    assert_response :success
    assert_select 'td', text: 'Montréal Canadiens'
    assert_select 'td', text: 'Boston Bruins'
    assert_select 'input[name=check]', count: 0

    assert_difference 'Subscription.where(league: "nhl").count', 1 do
      post teams_path, params: { league: 'nhl', slug: 'nhl-bos' }
    end
    assert_redirected_to teams_path(league: 'nhl')
    subscription = Subscription.find_by!(team_slug: 'nhl-bos')
    assert_equal 'Boston Bruins', subscription.name
    assert subscription.schedule_checked_at
    delete team_path(subscription.team_slug)
    assert_not Subscription.exists?(subscription.id)
  end

  test 'browse Slovak teams and subscribe without NHL or football requests' do
    FeedCache.create!(key: 'svk:schedule', fetched_at: Time.current, payload: {
      'teams' => [{ 'name' => 'HC Košice', 'slug' => 'svk-hc-kosice' },
                  { 'name' => 'HK Poprad', 'slug' => 'svk-hk-poprad' }], 'games' => []
    })
    get teams_path(league: 'extraliga')
    assert_response :success
    assert_select 'td', text: 'HC Košice'
    assert_select 'td', text: 'HK Poprad'
    assert_select 'input[name=check]', count: 0
    assert_difference 'Subscription.where(league: "extraliga").count', 1 do
      post teams_path, params: { league: 'extraliga', slug: 'svk-hk-poprad' }
    end
    assert_redirected_to teams_path(league: 'extraliga')
    assert_equal 'HK Poprad', Subscription.find_by!(team_slug: 'svk-hk-poprad').name
  end

  test 'unknown NHL team does not create a subscription' do
    assert_no_difference 'Subscription.count' do
      post teams_path, params: { league: 'nhl', slug: 'nhl-zzz' }
    end
    assert_redirected_to teams_path(league: 'nhl')
  end
end
