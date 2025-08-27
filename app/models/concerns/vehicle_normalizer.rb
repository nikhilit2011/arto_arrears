# frozen_string_literal: true
module VehicleNormalizer
  extend ActiveSupport::Concern

  def normalize_vehicle(v)
    v.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end
end
