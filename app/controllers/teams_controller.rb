# frozen_string_literal: true
# typed: true

class TeamsController < ApplicationController
  def index
    @settings = Setting.instance
    @league = params[:league].presence_in(Subscription::LEAGUES.keys) || 'football'
    @sport = params[:sport].presence_in(Setting::SPORTS) || @settings.sport
    @competitions = @settings.competitions_for(@sport)
    @competition = params[:competition].presence || @competitions.first
    @subscribed = Subscription.where(league: @league).pluck(:team_slug).to_set
    @teams = []
    @checked = nil

    if Subscription::HOCKEY_LEAGUES.include?(@league)
      @teams = hockey_client(@league).teams
      @competition_name = Subscription::LEAGUES.fetch(@league)
      return
    end

    if @competition
      directory = TeamDirectory.new
      @teams = directory.teams(@competition, sport: @sport)
      @competition_name = directory.last_competition_name
    end

    if params[:check].present?
      @checked = TeamDirectory.new.lookup(params[:check].to_s.strip, sport: @sport)
      @check_query = params[:check].to_s.strip
      @checked ||= false # distinguish "no result" from "not checked"
    end
  rescue Sportscore::Error, NhlClient::Error, SlovakHockeyClient::Error => e
    @error = e.message
  end

  def create
    slug = params[:slug].to_s.strip
    league = params[:league].presence_in(Subscription::LEAGUES.keys) || 'football'
    name = params[:name].presence
    logo = params[:logo].presence
    if Subscription::HOCKEY_LEAGUES.include?(league)
      team = hockey_client(league).teams.find { |entry| entry.slug == slug }
      return redirect_to teams_path(league: league), alert: 'Unknown hockey team' unless team

      name = team.name
      logo = team.logo
    elsif name.nil?
      info = TeamDirectory.new.lookup(slug, sport: Setting.instance.sport)
      if info
        name = info&.name
        logo = info&.logo
      end
    end
    subscription = Subscription.find_or_create_by(team_slug: slug, league: league) do |s|
      s.name = name
      s.logo = logo
    end
    return redirect_back_or_to teams_path, alert: "Invalid team slug: #{slug}" unless subscription.persisted?

    notice = "Subscribed to #{slug}"
    begin
      Poller.new.refresh(subscription)
    rescue Sportscore::Error, NhlClient::Error, SlovakHockeyClient::Error => e
      notice += " (fixture sync failed: #{e.message} — will retry on next poll)"
    end
    redirect_to teams_path(league: league, sport: params[:sport], competition: params[:competition]),
                notice: notice
  end

  def destroy
    slug = params[:id].to_s.strip
    Subscription.find_by(team_slug: slug)&.destroy_with_matches!
    redirect_back_or_to root_path, notice: "Unsubscribed from #{slug}"
  end

  private

  def hockey_client(league)
    league == 'nhl' ? NhlClient.new : SlovakHockeyClient.new
  end
end
