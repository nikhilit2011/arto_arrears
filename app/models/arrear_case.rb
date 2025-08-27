class ArrearCase < ApplicationRecord
  before_validation :normalize!
  validates :vehicle_number, :normalized_vehicle_number, presence: true
  validates :normalized_vehicle_number, uniqueness: true

  enum tax_paid_status: { unpaid: false, paid: true } # if using boolean

  def normalize!
    self.normalized_vehicle_number = vehicle_number.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  def self.ransackable_attributes(_ = nil)
    %w[
      vehicle_number normalized_vehicle_number vehicle_type tax_arrear_from
      first_notice_date first_notice_tax_cents first_notice_penalty_cents first_notice_total_cents
      second_notice_date second_notice_tax_cents second_notice_penalty_cents second_notice_total_cents
      recovery_challan_date recovery_challan_tax_cents recovery_challan_penalty_cents
      tax_paid_status tax_paid_date tax_paid_amount_cents remarks created_at updated_at
    ]
  end
end
