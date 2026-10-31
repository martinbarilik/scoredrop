# frozen_string_literal: true
# typed: true

require 'net/http'
require 'nokogiri'

class SlovakHockeyClient
  class Error < StandardError; end

  def teams
    league_data.fetch('teams').map do |team|
      TeamDirectory::Team.new(name: team.fetch('name'), slug: team.fetch('slug'), logo: team['logo'])
    end
  end

  def schedule(team_slug)
    data = league_data
    raise Error, 'Unknown Slovak team' unless data.fetch('teams').any? { |team| team['slug'] == team_slug }

    data.fetch('games').select { |game| game.fetch('team_slugs').include?(team_slug) }.map do |game|
      attributes = game.except('team_slugs').symbolize_keys
      attributes[:kickoff_at] = Time.iso8601(attributes.fetch(:kickoff_at))
      attributes
    end
  end

  # Shares the hockey client signature with NhlClient: HockeyPoller always
  # passes `date`, but this provider locates the match page purely from `id`,
  # so the kwarg is intentionally unused.
  def result(id, date:) # rubocop:disable Lint/UnusedMethodArgument
    raise Error, 'Invalid Slovak match ID' unless id.match?(/\A\d+-\d+\z/)

    tournament, match = id.split('-')
    FeedCache.fetch("svk:result:#{id}", ttl: 1.hour) do
      doc = Nokogiri::HTML(get("/sk/stats/matches/#{tournament}/tipsport-liga/match/#{match}/overview"))
      detail = doc.at_css(".match-stats-detail[data-match-id='#{match}']")
      raise Error, 'Slovak match page layout changed' unless detail

      finished = detail.css('.matchPeriod-title').any? { |node| node.text.squish == 'Zápas sa skončil' }
      scores = %w[goalsHome goalsAway].map { |key| detail.at_css("[data-match-text='#{key}']")&.text&.strip }
      if finished && scores.all? { |score| score&.match?(/\A\d+\z/) }
        { 'status' => 'finished', 'home_score' => scores[0].to_i, 'away_score' => scores[1].to_i }
      else
        {}
      end
    end.symbolize_keys.presence
  end

  def parse_schedule(html)
    doc = Nokogiri::HTML(html)
    teams = doc.css('select#CompetitorID option').filter_map do |option|
      name = option.text.squish
      next unless option['value'].to_s.match?(/\A\d+\z/) && name.present?

      { 'name' => name, 'slug' => team_slug(name) }
    end.uniq { |team| team['slug'] }
    raise Error, 'Slovak team list missing or incomplete' if teams.size < 10

    games = doc.css('.program-results tr.fn-tap-row').filter_map do |row|
      images = row.css('td.td-mobile-w-team .hidden-xs img')
      link = row.css('a[href]').find { |node| node['href'].match?(%r{\A/sk/stats/matches/\d+/tipsport-liga/match/\d+}) }
      date = row.at_css('.match-date')&.text&.match(/\d{2}\.\d{2}\.\d{4}/)&.to_s
      time = row.css('td.match-hide-hover > div').map do |node|
        node.text.strip
      end.find { |text| text.match?(/\A\d{1,2}:\d{2}\z/) }
      next unless images.size == 2 && link && date && time && !%w[0:00 00:00].include?(time)

      tournament, id = link['href'].match(%r{/matches/(\d+)/tipsport-liga/match/(\d+)})[1, 2]
      kickoff = Time.find_zone!('Europe/Bratislava').strptime("#{date} #{time}", '%d.%m.%Y %H:%M')
      names = images.map { |image| image['alt'].to_s.squish }
      raise Error, 'Slovak fixture team names missing' if names.any?(&:blank?)

      slugs = names.map { |name| team_slug(name) }
      images.each_with_index do |image, index|
        team = teams.find { |entry| entry['slug'] == slugs[index] }
        team['logo'] ||= image['src'] if team && image['src'].to_s.start_with?('https://img.hockeyslovakia.sk/')
      end
      { 'key' => "svk:#{id}", 'slug' => "#{tournament}-#{id}", 'sport' => 'extraliga',
        'competition' => 'Slovak Extraliga', 'home' => names[0], 'away' => names[1],
        'kickoff_at' => kickoff.utc.iso8601, 'event_date' => kickoff.to_date.iso8601,
        'status' => 'upcoming', 'team_slugs' => slugs }
    end
    raise Error, 'Slovak schedule missing fixtures' if games.empty?

    { 'teams' => teams.sort_by { |team| team['name'] }, 'games' => games.uniq { |game| game['key'] } }
  end

  private

  def team_slug(name) = "svk-#{name.parameterize}"

  def league_data
    FeedCache.fetch('svk:schedule', ttl: 12.hours) do
      path = FeedCache.fetch('svk:competition', ttl: 1.day) do
        doc = Nokogiri::HTML(get('/sk'))
        link = doc.css('a[href]').find { |node| node['href'].match?(%r{\A/sk/stats/results/\d+/tipsport-liga\z}) }
        raise Error, 'Current Slovak league link missing' unless link

        { 'path' => link['href'] }
      end.fetch('path')
      parse_schedule(get(path))
    end
  end

  def get(path)
    uri = URI("https://www.hockeyslovakia.sk#{path}")
    4.times do
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        http.get(T.cast(uri, URI::HTTP).request_uri, 'Accept' => 'text/html',
                                                     'User-Agent' => 'Scoredrop schedule notifier')
      end
      if response.is_a?(Net::HTTPRedirection)
        target = URI.join(uri.to_s, response.fetch('location'))
        unless target.scheme == 'https' && target.host == 'www.hockeyslovakia.sk'
          raise Error,
                'Unexpected HockeySlovakia redirect'
        end

        uri = target
        next
      end
      raise Error, "HockeySlovakia HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      return response.body
    end
    raise Error, 'Too many HockeySlovakia redirects'
  rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
    raise Error, "HockeySlovakia request failed: #{e.class}"
  end
end
