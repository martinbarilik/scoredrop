require 'test_helper'

class HockeyPollerTest < ActiveSupport::TestCase
  class FakeClient
    attr_accessor :games, :final
    attr_reader :schedule_calls, :result_calls

    def initialize
      @games, @schedule_calls, @result_calls = [], 0, 0
    end

    def schedule(slug)
      @schedule_calls += 1
      @games
    end

    def result(id, date:)
      @result_calls += 1
      @final
    end
  end

  class Publisher
    attr_reader :titles
    attr_accessor :success

    def initialize
      @titles, @success = [], true
    end

    def publish(title:, **)
      @titles << title
      @success
    end
  end

  setup do
    @sub = Subscription.create!(team_slug: 'nhl-mtl', league: 'nhl', name: 'Montréal Canadiens')
    @client, @publisher = FakeClient.new, Publisher.new
    @settings = Setting.new(remind_minutes_before: 15)
    @poller = HockeyPoller.new(client: @client, publisher: @publisher, settings: @settings)
  end

  def game(time:, status: 'upcoming')
    { key: 'nhl:123', slug: '123', sport: 'nhl', home: 'Montréal Canadiens',
      away: 'Boston Bruins', competition: 'NHL', kickoff_at: time, status: status,
      home_score: nil, away_score: nil }
  end

  test 'schedules fetched twice daily and reminders and starts are DB driven' do
    travel_to Time.utc(2026, 10, 25, 16) do
      @client.games = [game(time: 15.minutes.from_now)]
      @poller.tick
      @poller.tick
      assert_equal 1, @client.schedule_calls
      assert_equal 1, @publisher.titles.count { |title| title.start_with?('Starting soon:') }
      assert_equal 0, @client.result_calls
      travel 15.minutes
      @poller.tick
      @poller.tick
      assert_equal 1, @publisher.titles.count { |title| title.start_with?('Scheduled start:') }
      assert_equal 1, @client.schedule_calls
      assert_equal 0, @client.result_calls
      travel 12.hours
      @poller.tick
      assert_equal 2, @client.schedule_calls
    end
  end

  test 'results wait three hours then retry hourly and notify once' do
    travel_to Time.utc(2026, 10, 25, 16) do
      @client.games = [game(time: 10.minutes.from_now)]
      @poller.tick
      travel 190.minutes
      @poller.tick
      @poller.tick
      assert_equal 1, @client.result_calls
      @client.final = game(time: 180.minutes.ago, status: 'finished').merge(home_score: 3, away_score: 2)
      travel 1.hour
      @poller.tick
      @poller.tick
      assert_equal 2, @client.result_calls
      assert_equal 1, @publisher.titles.count { |title| title.start_with?('Final:') }
    end
  end

  test 'first discovered finished games do not notify' do
    @client.games = [game(time: 4.hours.ago, status: 'finished').merge(home_score: 3, away_score: 2)]
    @poller.tick
    assert_empty @publisher.titles
    assert_equal 0, @client.result_calls
  end

  test 'failed reminder is retried without more API calls' do
    @client.games = [game(time: 10.minutes.from_now)]
    @publisher.success = false
    @poller.tick
    assert_nil Match.find_by!(key: 'nhl:123').notified_reminded_at
    @publisher.success = true
    @poller.tick
    assert Match.find_by!(key: 'nhl:123').notified_reminded_at
    assert_equal 1, @client.schedule_calls
  end

  test 'first discovered in-progress games still notify the final' do
    travel_to Time.utc(2026, 10, 25, 16) do
      @client.games = [game(time: 10.minutes.ago, status: 'in_progress')]
      @poller.tick
      travel 200.minutes
      @client.final = game(time: 210.minutes.ago, status: 'finished').merge(home_score: 3, away_score: 1)
      @poller.tick
      assert_equal 1, @publisher.titles.count { |title| title.start_with?('Final:') }
    end
  end

  test 'final notifications work when start notifications are disabled' do
    @settings.notify_start = false
    travel_to Time.utc(2026, 10, 25, 16) do
      @client.games = [game(time: 10.minutes.from_now)]
      @poller.tick
      travel 190.minutes
      @client.final = game(time: 180.minutes.ago, status: 'finished').merge(home_score: 3, away_score: 2)
      @poller.tick
      assert_equal 1, @publisher.titles.count { |title| title.start_with?('Final:') }
      assert_empty @publisher.titles.select { |title| title.start_with?('Scheduled start:') }
    end
  end

  test 'matches shared by two subscriptions notify only once' do
    Subscription.create!(team_slug: 'nhl-bos', league: 'nhl', name: 'Boston Bruins')
    @client.games = [game(time: 10.minutes.from_now)]
    @poller.tick
    assert_equal 2, Match.find_by!(key: 'nhl:123').subscriptions.count
    assert_equal 1, @publisher.titles.count { |title| title.start_with?('Starting soon:') }
  end

  test 'Slovak subscriptions use their own provider and the same cached deadline flow' do
    sub = Subscription.create!(team_slug: 'svk-hc-kosice', league: 'extraliga', name: 'HC Košice')
    slovak = FakeClient.new
    slovak.games = [game(time: 10.minutes.from_now).merge(
      key: 'svk:456', slug: '1197-456', sport: 'extraliga', home: 'HC Košice', competition: 'Slovak Extraliga')]
    poller = HockeyPoller.new(client: @client, slovak_client: slovak, publisher: @publisher, settings: @settings)
    poller.tick
    poller.tick
    assert_equal ['svk:456'], sub.matches.pluck(:key)
    assert_equal 1, slovak.schedule_calls
    assert_equal 1, @publisher.titles.count { |title| title.start_with?('Starting soon: HC Košice') }
    assert_equal 0, slovak.result_calls
  end

  test 'disabled notifications and postponed games stay silent' do
    @settings.assign_attributes(notify_start: false, notify_fulltime: false, remind_minutes_before: 0)
    @client.games = [game(time: 1.minute.ago, status: 'postponed')]
    @poller.tick
    assert_empty @publisher.titles
    assert_equal 0, @client.result_calls
  end
end
