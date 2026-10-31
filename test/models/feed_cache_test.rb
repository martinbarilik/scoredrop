# frozen_string_literal: true

require "test_helper"

class FeedCacheTest < ActiveSupport::TestCase
  test "fetch caches the payload for the ttl" do
    calls = 0
    FeedCache.fetch("k1", ttl: 1.hour) do
      calls += 1
      { "a" => 1 }
    end
    FeedCache.fetch("k1", ttl: 1.hour) do
      calls += 1
      { "a" => 2 }
    end
    assert_equal 1, calls
    assert_equal({ "a" => 1 }, FeedCache.fetch("k1", ttl: 1.hour) { flunk })

    travel 2.hours do
      result = FeedCache.fetch("k1", ttl: 1.hour) do
        calls += 1
        { "a" => 3 }
      end
      assert_equal({ "a" => 3 }, result)
    end
    assert_equal 2, calls
  end
end
