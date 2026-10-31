# frozen_string_literal: true
# typed: true

# Polls sportscore.com for subscribed teams and emits ntfy notifications on
# match start (primary), goals, and fulltime. Runs as a single background
# thread inside the web process (see config/initializers/poller.rb).
#
# Adaptive interval: fast poll while a tracked match is live or due to start
# soon (incl. delayed matches past kickoff still marked upcoming), slow
# otherwise — stays far below the API's ~10k requests/day allowance.
class Poller
  TRACK_PAST = 48.hours
  TRACK_FUTURE = 7.days
  # How often to probe league opponents for matches missing from the feeds.
  OPPONENT_SWEEP = 15.minutes

  class << self
    attr_reader :last_polled_at, :last_error

    def run!
      new.run!
    end
  end

  def initialize(client: Sportscore::Client.new, publisher: nil, settings: nil)
    @client = client
    @publisher = publisher
    @settings = settings # injectable for tests; nil = fresh from DB each tick
  end

  def run!
    Rails.logger.info("[poller] started")
    loop do
      if !@football_due_at || Time.current >= @football_due_at
        tick
        @football_due_at = Time.current + next_interval
      else
        HockeyPoller.new(publisher: @publisher, settings: @settings).tick
      end
      wait = [@football_due_at - Time.current, 1].max
      sleep(Subscription.where(league: Subscription::HOCKEY_LEAGUES).exists? ? [wait, 60].min : wait)
    end
  rescue StandardError => e
    # A bug in the loop itself — log and restart rather than die silently.
    Rails.logger.error("[poller] crashed: #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
    sleep 60
    retry
  end

  # One poll cycle. Errors per-team are isolated so one bad slug doesn't
  # stop the rest.
  def tick
    self.class.instance_variable_set(:@last_error, nil)
    HockeyPoller.new(publisher: @publisher, settings: @settings).tick
    Subscription.where(league: 'football').ordered.find_each do |subscription|
      sync_team(subscription)
    rescue StandardError => e
      self.class.instance_variable_set(:@last_error, "team #{subscription.team_slug}: #{e.message}")
      Rails.logger.warn("[poller] team #{subscription.team_slug}: #{e.class}: #{e.message}")
    end

    sync_live_feed
    discover_missing_matches

    process_tracked_matches
    # Remove matches no subscription claims (e.g. leftovers from before
    # match_subscriptions existed) and finished matches past the tracking
    # window — they can never notify again.
    Match.where.missing(:match_subscriptions).destroy_all
    Match.finished.where("kickoff_at < ?", Time.current - TRACK_PAST).destroy_all
  ensure
    self.class.instance_variable_set(:@last_polled_at, Time.current)
  end

  # Synchronous refresh for one subscription — used by the UI right after
  # subscribing so matches show up immediately instead of waiting a cycle.
  def refresh(subscription)
    if Subscription::HOCKEY_LEAGUES.include?(subscription.league)
      return HockeyPoller.new(publisher: @publisher, settings: @settings).tick(subscription: subscription)
    end

    sync_team(subscription)
    sync_live_feed
    discover_for(subscription)
    process_tracked_matches
  end

  def next_interval
    now = Time.current
    football = Match.where.not(sport: Subscription::HOCKEY_LEAGUES)
    urgent = football.live.exists? ||
             football.upcoming.where(kickoff_at: now..(now + settings.live_window)).exists? ||
             # delayed kickoffs — bounded so stale "upcoming" rows the API
             # never updates (cancelled/postponed) don't pin the fast interval
             football.upcoming.where(kickoff_at: (now - TRACK_PAST)..now).exists?
    urgent ? settings.poll_interval : settings.idle_poll_interval
  end

  private

  # Injected settings (tests) or a fresh row each call so edits apply
  # without restart.
  def settings = @settings || Setting.instance

  # Rebuilt per call in production so ntfy edits apply without restart.
  def publisher
    @publisher || Ntfy::Publisher.new(
      url: settings.ntfy_url, topic: settings.ntfy_topic,
      token: settings.ntfy_token, priority: settings.ntfy_priority
    )
  end

  def sync_team(subscription)
    # Farthest-first, capped at 30 server-side — a smaller limit silently
    # drops the *nearest* fixtures.
    data = @client.team(sport: settings.sport, slug: subscription.team_slug, limit: 30)
    raise Sportscore::Error, data["error"] if data["error"]

    # Cache the resolved team name/logo for the UI.
    if (team = data["team"]).is_a?(Hash)
      subscription.update_columns(name: team["name"], logo: team["logo"], updated_at: Time.current)
    end

    # The API returns fixtures farthest-first — process soonest first.
    Array(data["matches"]).sort_by { |m| m["time"].to_s }.each do |m|
      if (match = upsert_match(m))
        MatchSubscription.find_or_create_by!(match: match, subscription: subscription)
      end
    end
  end

  # The team endpoint caps at ~30 farthest-out fixtures, so near-term matches
  # can be missing from it. The global matches feed carries live/recent/imminent
  # fixtures — pick up any involving subscribed teams and link them.
  def sync_live_feed
    subs = Subscription.where(league: 'football').where.not(name: nil).to_a
    return if subs.empty?

    data = @client.matches(sport: settings.sport, limit: 50)
    raise Sportscore::Error, data["error"] if data["error"]

    Array(data["matches"]).each do |m|
      subs.each do |sub|
        next unless [m["home"], m["away"]].any? { |n| team_name_match?(n, sub) }

        match = upsert_match(m)
        MatchSubscription.find_or_create_by!(match: match, subscription: sub) if match
      end
    end
  rescue Sportscore::Error => e
    Rails.logger.warn("[poller] matches feed: #{e.message}")
  end

  # Some matches never appear in any feed: the team endpoint only lists
  # upcoming fixtures (capped at 30 farthest-out, so the nearest ones drop
  # off entirely), and the global feed is capped at 50. But match slugs are
  # derivable — "{team}-vs-{opponent}" resolves in the detail endpoint
  # regardless of order — so we probe every league pairing from standings and
  # upsert whatever falls inside the tracking window. Rate-limited by
  # OPPONENT_SWEEP to stay within the API budget.
  def discover_missing_matches(now = Time.current)
    return if @last_sweep && now - @last_sweep < OPPONENT_SWEEP

    @last_sweep = now

    Subscription.where(league: 'football').find_each { |sub| discover_for(sub) }
  end

  def discover_for(subscription)
    league_opponents(subscription).each do |opponent|
      slug = [subscription.team_slug, opponent].sort.join("-vs-")
      # An unfinished fixture for this pairing is already tracked and
      # detail-polled — probing can't discover anything new. A finished
      # one must NOT skip: the slug then resolves to the next fixture.
      next if subscription.matches.where(slug: slug).where.not(status: "finished").exists?

      m = @client.match(sport: settings.sport, slug: slug)["match"]
      next unless m.is_a?(Hash) && m["url"].present? && m["time"].present?
      next unless m["time"].to_time.between?(Time.current - TRACK_PAST, Time.current + TRACK_FUTURE)

      if (match = upsert_match(m))
        MatchSubscription.find_or_create_by!(match: match, subscription: subscription)
      end
    rescue Sportscore::Error => e
      Rails.logger.warn("[poller] probe #{slug}: #{e.message}")
    end
  rescue StandardError => e
    Rails.logger.warn("[poller] discovery #{subscription.team_slug}: #{e.class}: #{e.message}")
  end

  # The subscription's league, inferred from its tracked matches' competition
  # names — they slugify to standings slugs ("English Premier League" ->
  # "english-premier-league"). Returns opponent team_slugs.
  def league_opponents(subscription)
    name = subscription.matches.where.not(competition: nil)
                       .group(:competition).order(Arel.sql("count(*) DESC")).limit(1).pick(:competition)
    return [] unless name

    slug = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    data = @client.standings(sport: settings.sport, slug: slug)
    rows = Array(data["tables"]).flat_map { |t| Array(t["rows"]) }
    rows.filter_map { |r| r["team_slug"] } - [subscription.team_slug]
  end

  # API names vary ("FC Barcelona" vs subscription "Barcelona") — match on
  # normalized containment either direction.
  def team_name_match?(api_name, subscription)
    a = api_name.to_s.downcase
    s = subscription.name.to_s.downcase
    a.length >= 3 && s.length >= 3 && (a.include?(s) || s.include?(a))
  end

  def upsert_match(payload)
    key = Match.key_for(payload)

    return unless key

    match = Match.find_or_initialize_by(key: key)

    # Finished is terminal — a stale feed that still reports the fixture
    # as upcoming/live must not regress status or wipe the final score.
    unless match.finished? && payload["status"] != "finished"
      match.assign_attributes(
        slug: Match.slug_for(payload) || match.slug.presence || key,
        sport: settings.sport,
        home: payload["home"],
        away: payload["away"],
        competition: payload["competition"],
        kickoff_at: payload["time"],
        status: payload["status"].presence || match.status.presence || "upcoming",
        home_score: payload["home_score"].nil? ? match.home_score : payload["home_score"],
        away_score: payload["away_score"].nil? ? match.away_score : payload["away_score"]
      )

      # First discovered already finished — pre-mark so it can never emit a
      # fulltime notification (the "was tracked" check lives in the flag,
      # not in which notifications happened to be enabled or delivered).
      match.notified_finished_at = Time.current if match.new_record? && match.finished?
      match.save! if match.changed? || match.new_record?
    end
    match
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[poller] upsert #{key}: #{e.message}")
    nil
  end

  def process_tracked_matches
    now = Time.current
    scoped = Match.where.not(sport: Subscription::HOCKEY_LEAGUES).joins(:match_subscriptions).distinct
    scoped.where(kickoff_at: (now - TRACK_PAST)..(now + TRACK_FUTURE))
          .or(scoped.live)
          .find_each do |match|
      detail = sync_match_detail(match, now)
      notify_reminder(match, now)
      notify_started(match)
      notify_goals(match, detail) if match.live?
      notify_finished(match, now)
    rescue StandardError => e
      # One bad match row must not skip the rest of the cycle.
      Rails.logger.warn("[poller] match #{match.slug}: #{e.class}: #{e.message}")
    end
  end

  # The fixture feeds only reliably list upcoming matches — a match that has
  # kicked off keeps reporting "upcoming" (or drops out entirely). The match
  # detail endpoint is authoritative, so poll it for live or due matches and
  # sync status/scores from it. Returns the detail payload for reuse.
  def sync_match_detail(match, now)
    return unless match.live? || (match.upcoming? && match.kickoff_at && match.kickoff_at <= now)

    detail = @client.match(sport: match.sport, slug: match.slug)
    payload = detail["match"] || {}
    match.update!(
      status: payload["status"].presence || match.status,
      home_score: payload["home_score"].presence || match.home_score,
      away_score: payload["away_score"].presence || match.away_score
    )
    detail
  rescue Sportscore::Error => e
    Rails.logger.warn("[poller] match detail #{match.slug}: #{e.message}")
    nil
  end

  def notify_reminder(match, now)
    minutes = settings.remind_minutes_before
    return if minutes <= 0 || !match.upcoming? || match.notified_reminded_at
    return unless match.kickoff_at&.between?(now, now + minutes.minutes)

    if publish("Starting soon: #{match.home} vs #{match.away}",
               "#{match.competition} — kickoff at #{match.kickoff_at.utc.strftime('%H:%M UTC')}",
               tags: %w[alarm_clock soccer])
      match.update!(notified_reminded_at: now)
    end
  end

  def notify_started(match)
    return unless settings.notify?(:start)
    return unless match.live? && match.notified_started_at.nil?

    if publish("Kickoff: #{match.home} vs #{match.away}",
               "#{match.competition} — match is live",
               tags: %w[soccer])
      match.update!(notified_started_at: Time.current)
    end
  end

  def notify_goals(match, detail = nil)
    return unless settings.notify?(:goals)

    detail ||= @client.match(sport: match.sport, slug: match.slug)
    payload = detail["match"] || {}
    incidents = Array(payload["incidents"])

    known = match.notified_incidents.pluck(:incident_key).to_set
    incidents.each do |incident|
      next unless incident["is_goal"]

      key = "#{incident['time']}:#{incident['side']}:#{incident['player']}"
      next if known.include?(key)

      score = "#{incident['home_score']}-#{incident['away_score']}"
      next unless publish("Goal! #{match.home} #{score} #{match.away}",
                          "#{incident['player']} (#{incident['time']}') — #{match.competition}",
                          tags: %w[soccer trophy])

      match.notified_incidents.create!(incident_key: key)
    end

    # Fallback when the API reports no incidents: score diff. The match's
    # stored scores can't be the watermark — sync_match_detail already
    # advanced them from this same payload, so the diff would always be 0
    # (and a failed publish would never retry). Notified scorelines serve
    # instead: the first observed one is the baseline, anything unseen
    # above it is a goal, and a failed publish leaves no row -> retried.
    if incidents.none?
      new_home = payload["home_score"].to_i
      new_away = payload["away_score"].to_i
      key = "score:#{new_home}:#{new_away}"
      notified_total = known.filter_map { |k| k.split(":").last(2).map(&:to_i).sum if k.start_with?("score:") }.max

      if notified_total.nil?
        match.notified_incidents.create!(incident_key: key)
      elsif !known.include?(key) && (new_home + new_away) > notified_total &&
            publish("Goal! #{match.home} #{new_home}-#{new_away} #{match.away}",
                    match.competition.to_s, tags: %w[soccer trophy])
        match.notified_incidents.create!(incident_key: key)
      end

      match.update!(home_score: new_home, away_score: new_away)
    elsif incidents.any?
      match.update!(home_score: payload["home_score"], away_score: payload["away_score"])
    end
  rescue Sportscore::Error => e
    Rails.logger.warn("[poller] match detail #{match.slug}: #{e.message}")
  end

  def notify_finished(match, now)
    return unless settings.notify?(:fulltime)
    return unless match.finished? && match.notified_finished_at.nil?

    if publish("Fulltime: #{match.home} #{match.home_score}-#{match.away_score} #{match.away}",
               match.competition.to_s, tags: %w[checkered_flag])
      match.update!(notified_finished_at: now)
    end
  end

  def publish(title, message, tags: [])
    ok = publisher.publish(title: title, message: message, tags: tags)
    Rails.logger.info("[poller] notify#{ok ? '' : ' (failed)'}: #{title}")
    ok
  end
end
