class TaxPayment < ApplicationRecord
  validates :vehicle_number, presence: true

  def self.ransackable_attributes(_ = nil)
    %w[vehicle_number normalized_vehicle_number payment_date amount_cents payment_ref source_file matched created_at updated_at]
  end
end
