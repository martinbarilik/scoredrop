# frozen_string_literal: true
# typed: true

require 'net/http'
require 'json'

class NhlClient
  class Error < StandardError; end

  def teams
    data = FeedCache.fetch('nhl:teams', ttl: 1.day) do
      response = get('/v1/standings/now')

      unless response['standings'].is_a?(Array) && response['standings'].any?
        raise Error, 'NHL team directory unavailable'
      end

      response
    end

    data.fetch('standings').map do |row|
      TeamDirectory::Team.new(
        name: row.fetch('teamName').fetch('default'),
        slug: "nhl-#{row.fetch('teamAbbrev').fetch('default').downcase}",
        logo: row['teamLogo']
      )
    end.sort_by(&:name)
  end

  def schedule(team_slug)
    raise Error, 'Invalid NHL team code' unless team_slug.match?(/\Anhl-[a-z]{3}\z/)

    data = FeedCache.fetch("nhl:schedule:#{team_slug}", ttl: 12.hours) do
      response = get("/v1/club-schedule-season/#{team_slug.delete_prefix('nhl-').upcase}/now")
      raise Error, 'NHL schedule missing games' unless response['games'].is_a?(Array)

      response
    end
    data.fetch('games').map { |game| normalize(game) }
  end

  def result(id, date:)
    raise Error, 'Invalid NHL game date' unless date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    data = FeedCache.fetch("nhl:results:#{date}", ttl: 1.hour) do
      response = get("/v1/score/#{date}")
      raise Error, 'NHL results unavailable' unless response['games'].is_a?(Array)

      response
    end
    game = data.fetch('games').find { |g| g['id'].to_s == id.to_s }
    game && normalize(game)
  end

  def normalize(game)
    state = game.fetch('gameState')
    scheduled = game['gameScheduleState']
    status = if scheduled == 'TBD'
               'unscheduled'
             elsif %w[PPD CNCL].include?(scheduled)
               scheduled == 'PPD' ? 'postponed' : 'cancelled'
             elsif %w[FINAL OFF].include?(state)
               'finished'
             elsif %w[LIVE CRIT].include?(state)
               'in_progress'
             else
               'upcoming'
             end
    home = game.fetch('homeTeam')
    away = game.fetch('awayTeam')
    { key: "nhl:#{game.fetch('id')}", slug: game.fetch('id').to_s,
      sport: 'nhl', home: team_name(home), away: team_name(away), competition: 'NHL',
      kickoff_at: Time.iso8601(game.fetch('startTimeUTC')), event_date: game['gameDate'], status: status,
      home_score: home['score'], away_score: away['score'] }
  end

  private

  def team_name(team)
    [team.dig('placeName', 'default'),
     team.dig('commonName', 'default')].compact.join(' ').presence || team.fetch('abbrev')
  end

  def get(path)
    uri = URI("https://api-web.nhle.com#{path}")

    4.times do
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.get(T.cast(uri, URI::HTTP).request_uri, 'Accept' => 'application/json')
      end
      if response.is_a?(Net::HTTPRedirection)
        target = URI.join(uri.to_s, response.fetch('location'))
        raise Error, 'Unexpected NHL redirect' unless target.scheme == 'https' && target.host == 'api-web.nhle.com'

        uri = target
        next
      end
      raise Error, "NHL HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      return JSON.parse(response.body)
    end
    raise Error, 'Too many NHL redirects'
  rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
    raise Error, "NHL request failed: #{e.class}"
  end
end
