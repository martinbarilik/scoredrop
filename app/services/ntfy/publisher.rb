# frozen_string_literal: true
# typed: true

require "net/http"

module Ntfy
  # Publishes a notification to an ntfy topic via HTTP POST.
  # https://docs.ntfy.sh/publish/
  class Publisher
    TIMEOUT = 5

    def initialize(url:, topic:, token: nil, priority: nil)
      @url = url.to_s.sub(%r{/+$}, "")
      @topic = topic
      @token = token.presence
      @priority = priority.presence
    end

    attr_reader :last_error

    def configured? = @url.present? && @topic.present?

    # Returns true on success, false otherwise (errors are logged, not raised).
    def publish(title:, message:, tags: [], priority: nil)
      @last_error = nil
      unless configured?
        @last_error = "ntfy server/topic not configured"
        return false
      end

      uri = URI("#{@url}/#{URI.encode_www_form_component(@topic)}")
      request = Net::HTTP::Post.new(uri)
      request["Title"] = title.to_s
      request["Priority"] = (priority || @priority).to_s if priority || @priority
      request["Tags"] = tags.join(",") if tags.any?
      request["Authorization"] = "Bearer #{@token}" if @token
      request.body = message.to_s

      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        @last_error = "HTTP #{response.code}"
        Rails.logger.warn("[ntfy] POST #{uri} -> HTTP #{response.code}")
        return false
      end

      true
    rescue SocketError, SystemCallError, Timeout::Error, URI::InvalidURIError => e
      @last_error = "#{e.class}: #{e.message}"
      Rails.logger.warn("[ntfy] publish failed: #{e.class}: #{e.message}")
      false
    end
  end
end
