# app/services/tax_payment_reconciler.rb
class TaxPaymentReconciler
  # Enforce: for each vehicle, keep ONLY the earliest payment (by payment_date).
  # Others become matched=false. ArrearCase is updated from that earliest row.
  #
  # Usage:
  #   TaxPaymentReconciler.earliest_only!(normalized_vehicle_numbers: ["UK07TA1234", ...])
  #   # or across all:
  #   TaxPaymentReconciler.earliest_only!
  #
  def self.earliest_only!(normalized_vehicle_numbers: nil)
    scope = TaxPayment.where.not(normalized_vehicle_number: nil)
    scope = scope.where(normalized_vehicle_number: normalized_vehicle_numbers) if normalized_vehicle_numbers.present?

    nvns = scope.distinct.pluck(:normalized_vehicle_number)
    return { vehicles: 0, kept: 0 } if nvns.empty?

    adapter = ActiveRecord::Base.connection.adapter_name.to_s.downcase
    chosen_by_nvn = {}

    if adapter.include?("postgres")
      # Pick earliest by (payment_date ASC NULLS LAST, id ASC) for each NVN using DISTINCT ON
      chosen_rows = TaxPayment
        .where(normalized_vehicle_number: nvns)
        .select("DISTINCT ON (normalized_vehicle_number) id, normalized_vehicle_number")
        .order("normalized_vehicle_number, payment_date ASC NULLS LAST, id ASC")

      chosen_rows.each { |row| chosen_by_nvn[row.normalized_vehicle_number] = row.id }
    else
      # SQLite/MySQL fallback — do it in Ruby
      TaxPayment.where(normalized_vehicle_number: nvns).find_each(batch_size: 1000) do |tp|
        arr = (chosen_by_nvn[tp.normalized_vehicle_number] ||= [])
        arr << tp
      end
      chosen_by_nvn.transform_values! do |rows|
        rows.min_by { |r| [r.payment_date || Date.new(9999, 1, 1), r.id] }.id
      end
    end

    keep_ids = chosen_by_nvn.values

    # Set matched=false for all rows of these vehicles, then matched=true for the chosen ones
    TaxPayment.where(normalized_vehicle_number: nvns).update_all(matched: false)
    TaxPayment.where(id: keep_ids).update_all(matched: true)

    # Update ArrearCase fields from chosen earliest payment
    chosen_map = TaxPayment.where(id: keep_ids).pluck(:normalized_vehicle_number, :payment_date, :amount_cents).to_h
    ArrearCase.where(normalized_vehicle_number: nvns).find_each do |ac|
      if (tuple = chosen_map[ac.normalized_vehicle_number])
        pdate, cents = tuple[1], tuple[2]
        ac.update!(
          tax_paid_status: true,
          tax_paid_date: pdate,
          tax_paid_amount_cents: cents
        )
      end
    end

    { vehicles: nvns.size, kept: keep_ids.size }
  end
end
