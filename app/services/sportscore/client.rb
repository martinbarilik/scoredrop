# frozen_string_literal: true
# typed: true

require "net/http"
require "json"

module Sportscore
  # Thin client for the free sportscore.com widget API.
  # https://sportscore.com/developers/ — no API key, JSON, ~60s edge cache.
  class Client
    BASE_URL = "https://sportscore.com"
    TIMEOUT = 10

    # Recent + upcoming fixtures for a team slug, e.g. "barcelona".
    def team(sport:, slug:, limit: 10)
      get("/api/widget/team/", sport: sport, slug: slug, limit: limit)
    end

    # Single match detail (adds live_minute + incidents).
    def match(sport:, slug:)
      get("/api/widget/match/", sport: sport, slug: slug)
    end

    # Live + recent fixtures across competitions — catches imminent matches
    # the team endpoint's hard-capped feed misses.
    def matches(sport:, limit: 50)
      get("/api/widget/matches/", sport: sport, limit: limit)
    end

    # League standings — rows include team_slug, which doubles as team
    # discovery since the API has no teams-listing endpoint.
    def standings(sport:, slug:)
      get("/api/widget/standings/", sport: sport, slug: slug)
    end

    private

    def get(path, params)
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                     open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.get(T.cast(uri, URI::HTTP).request_uri, "accept" => "application/json")
      end

      raise Error, "HTTP #{response.code} for #{uri}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "invalid JSON from #{uri}: #{e.message}"
    rescue SocketError, SystemCallError, Timeout::Error => e
      raise Error, "request to #{uri} failed: #{e.class}: #{e.message}"
    end
  end
end
