# frozen_string_literal: true
# typed: true

class HockeyPoller
  def initialize(client: NhlClient.new, slovak_client: SlovakHockeyClient.new, publisher: nil, settings: nil)
    @clients = { 'nhl' => client, 'extraliga' => slovak_client }
    @publisher = publisher
    @settings = settings
  end

  def tick(subscription: nil)
    scope = Subscription.where(league: Subscription::HOCKEY_LEAGUES)
    scope = scope.where(id: subscription.id) if subscription
    scope.find_each do |sub|
      sync_schedule(sub)
    rescue StandardError => e
      Rails.logger.warn("[hockey] schedule #{sub.team_slug}: #{e.class}: #{e.message}")
    end
    Match.where(sport: Subscription::HOCKEY_LEAGUES).joins(:match_subscriptions).distinct
         .where(kickoff_at: 7.days.ago..7.days.from_now).find_each do |match|
      process(match)
    rescue StandardError => e
      Rails.logger.warn("[hockey] match #{match.key}: #{e.class}: #{e.message}")
    end
  end

  private

  def settings = @settings || Setting.instance

  def publisher
    @publisher || Ntfy::Publisher.new(
      url: settings.ntfy_url,
      topic: settings.ntfy_topic,
      token: settings.ntfy_token,
      priority: settings.ntfy_priority
    )
  end

  def sync_schedule(subscription)
    return if subscription.schedule_checked_at && subscription.schedule_checked_at > 12.hours.ago

    games = @clients.fetch(subscription.league).schedule(subscription.team_slug)
    games.each do |attributes|
      next unless attributes[:kickoff_at].between?(2.days.ago, 14.days.from_now)

      match = Match.find_or_initialize_by(key: attributes[:key])
      unless match.finished? && attributes[:status] != 'finished'
        if (attributes[:kickoff_at] > Time.current && attributes[:status] == 'upcoming') ||
           attributes[:status] == 'in_progress'
          match.schedule_tracked_at ||= Time.current
        end
        match.assign_attributes(attributes)
        match.save!
      end
      MatchSubscription.find_or_create_by!(match: match, subscription: subscription)
    end
    subscription.update!(schedule_checked_at: Time.current)
  rescue StandardError
    subscription.update_columns(schedule_checked_at: 11.hours.ago)
    raise
  end

  def process(match)
    now = Time.current
    minutes = settings.remind_minutes_before
    if match.upcoming? && minutes.positive? &&
       match.kickoff_at.between?(now, now + minutes.minutes) &&
       !match.notified_reminded_at &&
       publisher.publish(
         title: "Starting soon: #{match.home} vs #{match.away}",
         message: "#{match.competition} — scheduled start #{match.kickoff_at.utc.strftime('%H:%M UTC')}",
         tags: %w[alarm_clock ice_hockey]
       )

      match.update!(notified_reminded_at: now)
    end
    if settings.notify?(:start) && %w[upcoming in_progress].include?(match.status) &&
       match.schedule_tracked_at &&
       match.kickoff_at.between?(now - 30.minutes, now) &&
       !match.notified_started_at &&
       publisher.publish(
         title: "Scheduled start: #{match.home} vs #{match.away}",
         message: "#{match.competition} — scheduled start time reached (not live-confirmed)",
         tags: %w[ice_hockey]
       )

      match.update!(notified_started_at: now)
    end
    if !match.finished? && !%w[postponed cancelled unscheduled].include?(match.status) &&
       match.kickoff_at <= now - 3.hours && match.kickoff_at >= now - 2.days &&
       (!match.result_checked_at || match.result_checked_at <= now - 1.hour)
      match.update!(result_checked_at: now)
      date = match.event_date || match.kickoff_at.in_time_zone('America/New_York').to_date
      result = @clients.fetch(match.sport).result(match.slug, date: date.iso8601)
      match.update!(result.except(:key, :slug)) if result
    end
    unless match.finished? && match.schedule_tracked_at && settings.notify?(:fulltime) && !match.notified_finished_at
      return
    end

    if publisher.publish(
      title: "Final: #{match.home} #{match.home_score}-#{match.away_score} #{match.away}",
      message: match.competition, tags: %w[checkered_flag ice_hockey]
    )
      match.update!(notified_finished_at: now)
    end
  end
end
