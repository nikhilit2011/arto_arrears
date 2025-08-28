# app/models/tax_payment.rb
require "digest"

class TaxPayment < ApplicationRecord
  before_validation :normalize!
  before_validation :set_fingerprint!

  validates :vehicle_number, presence: true
  validates :fingerprint, presence: true, uniqueness: true

  # Normalize vehicle number for matching
  def normalize!
    self.normalized_vehicle_number = vehicle_number.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  # Stable, file-agnostic idempotency key:
  # (NVN | payment_date | amount_cents | UPPER(payment_ref))
  # -> ensures same payment from different XLS files dedupes
  def set_fingerprint!
    key = [
      normalized_vehicle_number.to_s.strip,
      (payment_date&.to_s || ""),
      amount_cents.to_i.to_s,
      (payment_ref || "").strip.upcase
    ].join("|")

    self.fingerprint = Digest::MD5.hexdigest(key)
  end

  def self.ransackable_attributes(_ = nil)
    %w[
      vehicle_number normalized_vehicle_number payment_date amount_cents
      payment_ref source_file matched created_at updated_at fingerprint
    ]
  end
end
