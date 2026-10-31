require 'test_helper'

class NhlClientTest < ActiveSupport::TestCase
  class FakeClient < NhlClient
    attr_accessor :response
    attr_reader :requests

    def initialize
      @requests = []
    end

    private

    def get(path)
      @requests << path
      @response
    end
  end

  def game(state: 'FUT', schedule: 'OK')
    { 'id' => 123, 'gameState' => state, 'gameScheduleState' => schedule,
      'startTimeUTC' => '2026-10-25T23:00:00Z',
      'homeTeam' => { 'placeName' => { 'default' => 'Montréal' }, 'commonName' => { 'default' => 'Canadiens' }, 'abbrev' => 'MTL', 'score' => 3 },
      'awayTeam' => { 'placeName' => { 'default' => 'Boston' }, 'commonName' => { 'default' => 'Bruins' }, 'abbrev' => 'BOS', 'score' => 2 } }
  end

  test 'normalizes NHL states and namespaced keys' do
    client = NhlClient.new
    assert_equal 'nhl:123', client.normalize(game)[:key]
    assert_equal 'Montréal Canadiens', client.normalize(game)[:home]
    assert_equal 'upcoming', client.normalize(game)[:status]
    assert_equal 'in_progress', client.normalize(game(state: 'LIVE'))[:status]
    assert_equal 'finished', client.normalize(game(state: 'OFF'))[:status]
    assert_equal 'finished', client.normalize(game(state: 'FINAL'))[:status]
    assert_equal 'postponed', client.normalize(game(schedule: 'PPD'))[:status]
    assert_equal 'cancelled', client.normalize(game(schedule: 'CNCL'))[:status]
  end

  test 'schedule cache persists across clients and expires after twelve hours' do
    travel_to Time.utc(2026, 10, 25, 12) do
      client = FakeClient.new
      client.response = { 'games' => [game] }
      assert_equal 'nhl:123', client.schedule('nhl-mtl').first[:key]
      other = FakeClient.new
      assert_equal 'nhl:123', other.schedule('nhl-mtl').first[:key]
      assert_empty other.requests
      travel 12.hours
      other.response = { 'games' => [game] }
      other.schedule('nhl-mtl')
      assert_equal 1, other.requests.size
    end
  end

  test 'team directory includes all returned teams and caches standings daily' do
    client = FakeClient.new
    client.response = { 'standings' => [
      { 'teamName' => { 'default' => 'Montréal Canadiens' }, 'teamAbbrev' => { 'default' => 'MTL' } },
      { 'teamName' => { 'default' => 'Boston Bruins' }, 'teamAbbrev' => { 'default' => 'BOS' } }
    ] }
    assert_equal %w[nhl-bos nhl-mtl], client.teams.map(&:slug)
    assert_equal 2, client.teams.size
    assert_equal 1, client.requests.size
  end
end
