# frozen_string_literal: true
# typed: true

class StatusController < ApplicationController
  def index
    @subscriptions = Subscription.ordered
    @settings = Setting.instance
    @matches = Match.order(
      Arel.sql(<<~SQL.squish)
        CASE WHEN status = 'live' THEN 0 WHEN status = 'upcoming' THEN 1 ELSE 2 END,
        CASE WHEN status != 'finished' THEN kickoff_at END ASC,
        CASE WHEN status = 'finished' THEN kickoff_at END DESC
      SQL
    ).page(params[:page]).per(25)
    @last_polled_at = Poller.last_polled_at
    @last_error = Poller.last_error
  end
end
