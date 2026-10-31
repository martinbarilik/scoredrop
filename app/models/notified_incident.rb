# frozen_string_literal: true
# typed: true

class NotifiedIncident < ApplicationRecord
  belongs_to :match
end
