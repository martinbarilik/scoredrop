# frozen_string_literal: true
# typed: true

class SettingsController < ApplicationController
  def show
    @settings = Setting.instance
  end

  def update
    Setting.instance.update!(
      sport: params[:sport].presence_in(Setting::SPORTS) || Setting.instance.sport,
      ntfy_url: params.dig(:ntfy, :url).presence,
      ntfy_topic: params.dig(:ntfy, :topic).presence,
      ntfy_token: params.dig(:ntfy, :token).presence,
      ntfy_priority: params.dig(:ntfy, :priority).presence,
      notify_start: params.dig(:notify, :start) == "1",
      notify_goals: params.dig(:notify, :goals) == "1",
      notify_fulltime: params.dig(:notify, :fulltime) == "1",
      remind_minutes_before: params[:remind_minutes_before].presence.to_i,
      poll_interval_seconds: params[:poll_interval_seconds].presence&.to_i || 120,
      idle_poll_interval_seconds: params[:idle_poll_interval_seconds].presence&.to_i || 900,
      live_window_seconds: params[:live_window_seconds].presence&.to_i || 1800
    )

    redirect_to settings_path, notice: "Settings saved"
  end

  # Publishes a test notification using the *submitted* form values, so a new
  # config can be verified before saving.
  def test_ntfy
    s = Setting.instance
    publisher = Ntfy::Publisher.new(
      url: params.dig(:ntfy, :url).presence || s.ntfy_url,
      topic: params.dig(:ntfy, :topic).presence || s.ntfy_topic,
      token: params.dig(:ntfy, :token).presence || s.ntfy_token,
      priority: params.dig(:ntfy, :priority).presence || s.ntfy_priority
    )

    if publisher.publish(title: "Scoredrop test",
                         message: "Connection check from Scoredrop",
                         tags: %w[white_check_mark soccer])
      redirect_to settings_path, notice: "Test notification sent — check your ntfy app."
    else
      redirect_to settings_path, alert: "Publish failed: #{publisher.last_error}"
    end
  end
end
