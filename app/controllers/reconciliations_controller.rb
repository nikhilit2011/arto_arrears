# app/controllers/reconciliations_controller.rb
require "csv"
require "ostruct"

class ReconciliationsController < ApplicationController
  # GET /reconciliation
  # Optional params:
  #   from=YYYY-MM-DD   (filter TaxPayment.payment_date >= from)
  #   to=YYYY-MM-DD     (filter TaxPayment.payment_date <= to)
  #   status=Pending|Cleared|Only Paid (No Arrear)|No Record
  def index
    # ---- 1) VEHICLE SET: ONLY ARREAR VEHICLES (INTERSECTION BEHAVIOR) ----
    arrear_nvns = ArrearCase.where.not(normalized_vehicle_number: nil)
                            .distinct
                            .pluck(:normalized_vehicle_number)

    # ---- 2) ARREAR TOTAL (WITH PRECEDENCE) ----
    arrear_rows = ArrearCase
      .where(normalized_vehicle_number: arrear_nvns)
      .pluck(
        :normalized_vehicle_number,
        :vehicle_number,
        :first_notice_total_cents,
        :second_notice_total_cents,
        :recovery_challan_tax_cents,
        :recovery_challan_penalty_cents
      )

    arrear_map = arrear_rows.to_h do |nvn, veh, first_c, second_c, rc_tax_c, rc_pen_c|
      rc_cents = rc_tax_c.to_i + rc_pen_c.to_i
      effective_cents =
        if rc_cents.positive?
          rc_cents
        elsif second_c.to_i.positive?
          second_c.to_i
        else
          first_c.to_i
        end
      [nvn, { vehicle_number: veh, arrear_total_cents: effective_cents }]
    end

    # ---- 3) PAYMENTS (OPTIONAL DATE WINDOW) ----
    pay_scope = TaxPayment.where(normalized_vehicle_number: arrear_nvns)
    if params[:from].present?
      from = Date.parse(params[:from]) rescue nil
      pay_scope = pay_scope.where("payment_date >= ?", from) if from
    end
    if params[:to].present?
      to = Date.parse(params[:to]) rescue nil
      pay_scope = pay_scope.where("payment_date <= ?", to) if to
    end

    paid_map = pay_scope.group(:normalized_vehicle_number).sum(:amount_cents)
    # => { "UK08TA4243" => cents_sum, ... }

    # ---- 4) BUILD ROWS (ONLY ARREAR VEHICLES) ----
    rows = arrear_nvns.map do |nvn|
      arrear_cents  = arrear_map.dig(nvn, :arrear_total_cents).to_i
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
        normalized_vehicle_number: nvn,
        vehicle_number:           (arrear_map.dig(nvn, :vehicle_number) || nvn),
        arrear_total:             (arrear_cents / 100.0),
        total_paid:               (paid_cents   / 100.0),
        balance:                  (balance_cents / 100.0),
        status:                   status
      )
    end

    # ---- 5) HIDE ZERO-PAID ROWS (YOUR REQUIREMENT) ----
    rows.reject! { |r| r.total_paid.zero? }

    # (Optional) If you want to *also* hide “Only Paid (No Arrear)” just uncomment:
    # rows.reject! { |r| r.status == "Only Paid (No Arrear)" }

    # ---- 6) OPTIONAL STATUS FILTER ----
    if params[:status].present?
      rows = rows.select { |r| r.status == params[:status] }
    end

    # ---- 7) SORT & PAGINATE ----
    rows.sort_by! { |r| -r.balance } # highest pending first
    @rows = Kaminari.paginate_array(rows).page(params[:page]).per(50)

    respond_to do |format|
      format.html
      format.csv { send_data to_csv(rows), filename: "reconciliation_#{Time.current.strftime('%Y%m%d_%H%M')}.csv" }
    end
  end

  private

  def to_csv(rows)
    CSV.generate(headers: true) do |csv|
      csv << ["Vehicle Number", "Normalized Vehicle", "Arrear Total (Rs.)", "Total Paid (Rs.)", "Balance (Rs.)", "Status"]
      rows.each do |r|
        csv << [r.vehicle_number, r.normalized_vehicle_number, r.arrear_total, r.total_paid, r.balance, r.status]
      end
    end
  end
end
