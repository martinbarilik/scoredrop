# frozen_string_literal: true
# typed: true

class FeedCache < ApplicationRecord
  def self.fetch(key, ttl:)
    record = find_by(key: key)
    return record.payload if record && record.fetched_at > ttl.ago

    payload = yield
    upsert({ key: key, payload: payload, fetched_at: Time.current }, unique_by: :key)
    payload
  end
end
