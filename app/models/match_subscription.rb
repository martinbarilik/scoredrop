# frozen_string_literal: true
# typed: true

class MatchSubscription < ApplicationRecord
  belongs_to :match
  belongs_to :subscription
end
