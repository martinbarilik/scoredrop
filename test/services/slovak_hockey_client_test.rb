require 'test_helper'

class SlovakHockeyClientTest < ActiveSupport::TestCase
  class FakeClient < SlovakHockeyClient
    attr_accessor :responses
    attr_reader :requests

    def initialize
      @responses, @requests = {}, []
    end

    private

    def get(path)
      @requests << path
      @responses.fetch(path)
    end
  end

  def schedule_html(date: '30.10.2026', time: '17:30', score: '')
    names = ['HC Košice', 'HK Poprad'] + 10.times.map { |i| "Hockey Team #{i}" }
    options = names.each_with_index.map { |name, i| "<option value='#{100 + i}'>#{name}</option>" }.join
    <<~HTML
      <select id="CompetitorID">#{options}</select>
      <div class="program-results"><table><tbody><tr class="fn-tap-row">
        <td class="td-mobile-w-team">
          <span class="visible-xs"><img alt="HC Košice"></span>
          <span class="hidden-xs"><img alt="HC Košice" src="https://img.hockeyslovakia.sk/Competitor/1/SVG/kosice.svg"></span>
        </td>
        <td class="td-mobile-w-score">#{score}</td>
        <td class="td-mobile-w-team team-away"><span class="hidden-xs"><img alt="HK Poprad"></span></td>
        <td class="match-hide-hover"><div class="match-date">Piatok #{date}</div><div>#{time}</div>
          <a href="/sk/stats/matches/1197/tipsport-liga/match/159942/preview">Pred zápasom</a>
        </td>
      </tr><tr class="fn-tap-row-sibbling"><td>Mobile duplicate</td></tr></tbody></table></div>
    HTML
  end

  def detail_html(finished:)
    <<~HTML
      <div class="match-stats-detail" data-match-id="159942">
        <span data-match-text="goalsHome">3</span><span data-match-text="goalsAway">2</span>
        <div class="matchPeriod-title">#{finished ? 'Zápas sa skončil' : '3. tretina'}</div>
      </div>
    HTML
  end

  test 'parses all teams and converts Bratislava times with daylight saving' do
    client = SlovakHockeyClient.new
    winter = client.parse_schedule(schedule_html)
    assert_equal 12, winter['teams'].size
    assert_equal 'svk-hc-kosice', winter['teams'].find { |team| team['name'] == 'HC Košice' }['slug']
    assert_equal 1, winter['games'].size
    game = winter['games'].first
    assert_equal 'svk:159942', game['key']
    assert_equal '1197-159942', game['slug']
    assert_equal '2026-10-30T16:30:00Z', game['kickoff_at']
    assert_equal '2026-10-30', game['event_date']
    assert_equal '2026-09-15T15:30:00Z', client.parse_schedule(schedule_html(date: '15.09.2026'))['games'].first['kickoff_at']
  end

  test 'a displayed score alone does not mean the match is finished' do
    client = SlovakHockeyClient.new
    data = client.parse_schedule(schedule_html(score: '<span class="matchresult">3</span>:2'))
    assert_equal 'upcoming', data['games'].first['status']
    assert_nil data['games'].first['home_score']
  end

  test 'rejects changed pages and schedules with unknown start times' do
    client = SlovakHockeyClient.new
    assert_raises(SlovakHockeyClient::Error) { client.parse_schedule('<html>Unavailable</html>') }
    assert_raises(SlovakHockeyClient::Error) { client.parse_schedule(schedule_html(time: '0:00')) }
  end

  test 'league discovery and schedules are shared and cached across clients' do
    client = FakeClient.new
    client.responses = {
      '/sk' => '<a href="/sk/stats/results/1197/tipsport-liga">Tipsport liga</a>',
      '/sk/stats/results/1197/tipsport-liga' => schedule_html
    }
    assert_equal 12, client.teams.size
    assert_equal 2, client.requests.size
    assert_equal 'HC Košice', client.schedule('svk-hc-kosice').first[:home]
    other = FakeClient.new
    assert_equal 1, other.schedule('svk-hk-poprad').size
    assert_empty other.requests
    assert_raises(SlovakHockeyClient::Error) { other.schedule('svk-unknown') }
  end

  test 'only explicit finished matches return scores and results are cached hourly' do
    travel_to Time.utc(2026, 10, 30, 20) do
      client = FakeClient.new
      path = '/sk/stats/matches/1197/tipsport-liga/match/159942/overview'
      client.responses[path] = detail_html(finished: false)
      assert_nil client.result('1197-159942', date: '2026-10-30')
      client.responses[path] = detail_html(finished: true)
      assert_nil client.result('1197-159942', date: '2026-10-30')
      assert_equal 1, client.requests.size
      travel 1.hour
      assert_equal({ status: 'finished', home_score: 3, away_score: 2 }, client.result('1197-159942', date: '2026-10-30'))
      assert_equal 2, client.requests.size
    end
  end

  test 'changed result pages fail rather than fabricate a result' do
    client = FakeClient.new
    client.responses['/sk/stats/matches/1197/tipsport-liga/match/159942/overview'] = '<html>Unavailable</html>'
    assert_raises(SlovakHockeyClient::Error) { client.result('1197-159942', date: '2026-10-30') }
  end
end
