# app/controllers/reconciliations_controller.rb
require "csv"
require "ostruct"

class ReconciliationsController < ApplicationController
  # GET /reconciliation
  # Optional params:
  #   from=YYYY-MM-DD   (limit payments >= from)
  #   to=YYYY-MM-DD     (limit payments <= to)
  #   status=Pending|Cleared|Only Paid (No Arrear)|No Record
  def index
    adapter = ActiveRecord::Base.connection.adapter_name.to_s.downcase

    # 1) VEHICLE SET: ONLY ARREAR VEHICLES (intersection)
    arrear_nvns = ArrearCase.where.not(normalized_vehicle_number: nil)
                            .distinct
                            .pluck(:normalized_vehicle_number)

    # 2) ARREAR MAP with precedence & 'Tax Arrear From'
    arrear_rows = ArrearCase
      .where(normalized_vehicle_number: arrear_nvns)
      .pluck(
        :normalized_vehicle_number,
        :vehicle_number,
        :tax_arrear_from,
        :first_notice_total_cents,
        :second_notice_total_cents,
        :recovery_challan_tax_cents,
        :recovery_challan_penalty_cents
      )

    arrear_map = arrear_rows.to_h do |nvn, veh, tax_from, first_c, second_c, rc_tax_c, rc_pen_c|
      rc_cents = rc_tax_c.to_i + rc_pen_c.to_i
      effective_cents =
        if rc_cents.positive?
          rc_cents
        elsif second_c.to_i.positive?
          second_c.to_i
        else
          first_c.to_i
        end
      [nvn, {
        vehicle_number:     veh,
        tax_arrear_from:    tax_from,
        arrear_total_cents: effective_cents
      }]
    end

    # 3) PAYMENTS with optional date window
    pay_scope = TaxPayment.where(normalized_vehicle_number: arrear_nvns)
    if params[:from].present?
      from = Date.parse(params[:from]) rescue nil
      pay_scope = pay_scope.where("payment_date >= ?", from) if from
    end
    if params[:to].present?
      to = Date.parse(params[:to]) rescue nil
      pay_scope = pay_scope.where("payment_date <= ?", to) if to
    end

    # Sum per vehicle
    paid_map = pay_scope.group(:normalized_vehicle_number).sum(:amount_cents)

    # Earliest receipt date + corresponding receipt no (payment_ref)
    earliest_date_map = {}
    earliest_ref_map  = {}

    if adapter.include?("postgres")
      # DISTINCT ON requires ORDER BY to start with the same expression(s)
      # Also: DON'T use find_each here; it injects ORDER BY id and breaks DISTINCT ON.
      earliest_rows = pay_scope
                        .reorder(nil) # clear any implicit ordering
                        .select("DISTINCT ON (normalized_vehicle_number)
                                 normalized_vehicle_number, payment_date, payment_ref, id")
                        .order("normalized_vehicle_number ASC, payment_date ASC NULLS FIRST, id ASC")

      earliest_rows.each do |r|
        earliest_date_map[r.normalized_vehicle_number] = r.payment_date
        earliest_ref_map[r.normalized_vehicle_number]  = r.payment_ref
      end
    else
      # Generic fallback (loads into memory then groups)
      pay_scope.to_a.group_by(&:normalized_vehicle_number).each do |nvn, rows|
        first_row = rows.min_by { |tp| [tp.payment_date || Date.new(9999,1,1), tp.id] }
        earliest_date_map[nvn] = first_row&.payment_date
        earliest_ref_map[nvn]  = first_row&.payment_ref
      end
    end

    # 4) BUILD ROWS (only arrear vehicles)
    rows = arrear_nvns.map do |nvn|
      ainfo         = arrear_map[nvn] || {}
      arrear_cents  = ainfo[:arrear_total_cents].to_i
      paid_cents    = paid_map[nvn].to_i
      balance_cents = arrear_cents - paid_cents

      status =
        if arrear_cents > 0 && balance_cents <= 0
          "Cleared"
        elsif arrear_cents > 0 && balance_cents > 0
          "Pending"
        elsif arrear_cents == 0 && paid_cents > 0
          "Only Paid (No Arrear)"
        else
          "No Record"
        end

      OpenStruct.new(
        vehicle_number:            (ainfo[:vehicle_number] || nvn),
        normalized_vehicle_number: nvn,
        tax_arrear_from:           ainfo[:tax_arrear_from],
        earliest_receipt_date:     earliest_date_map[nvn],
        earliest_receipt_ref:      earliest_ref_map[nvn],
        arrear_total:              (arrear_cents / 100.0),
        total_paid:                (paid_cents   / 100.0),
        balance:                   (balance_cents / 100.0),
        status:                    status
      )
    end

    # 5) HIDE rows where total paid is zero
    rows.reject! { |r| r.total_paid.zero? }

    # 6) Optional status filter
    if params[:status].present?
      rows = rows.select { |r| r.status == params[:status] }
    end

    # 7) Sort & paginate
    rows.sort_by! { |r| -r.balance }
    @rows = Kaminari.paginate_array(rows).page(params[:page]).per(50)

    respond_to do |format|
      format.html
      format.csv { send_data to_csv(rows), filename: "reconciliation_#{Time.current.strftime('%Y%m%d_%H%M')}.csv" }
    end
  end

  private

  def to_csv(rows)
    CSV.generate(headers: true) do |csv|
      csv << [
        "Sr no",
        "Vehicle Number",
        "Receipt Date (Earliest)",
        "Receipt No. (Earliest)",
        "Tax Arrear From",
        "Arrear Total (Rs.)",
        "Total Paid (Rs.)",
        "Balance (Rs.)",
        "Status"
      ]
      rows.each_with_index do |r,i|
        csv << [
          i + 1,
          r.normalized_vehicle_number,
          r.earliest_receipt_date,
          r.earliest_receipt_ref,
          r.tax_arrear_from,
          r.arrear_total,
          r.total_paid,
          r.balance,
          r.status
        ]
      end
    end
  end
end
