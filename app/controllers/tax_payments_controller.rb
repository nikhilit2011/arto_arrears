# app/controllers/tax_payments_controller.rb
require "csv"

class TaxPaymentsController < ApplicationController
  # before_action :ensure_creator!, only: [:imports]

  # GET /tax_payments
  def index
    @q = TaxPayment.ransack(params[:q])
    base_scope = @q.result.order(payment_date: :desc)

    adapter = ActiveRecord::Base.connection.adapter_name.to_s.downcase
    @grouped = (params[:group] == "vehicle")

    if @grouped
      # One row per vehicle (normalized_vehicle_number), aggregated fields
      if adapter.include?("postgres")
        rows = base_scope
          .select("normalized_vehicle_number,
                   MIN(vehicle_number) AS vehicle_number,
                   MIN(payment_date)   AS earliest_payment_date,
                   SUM(amount_cents)   AS total_amount_cents,
                   MIN(payment_ref)    AS payment_ref,
                   BOOL_OR(matched)    AS any_matched")
          .group("normalized_vehicle_number")
          .order("MIN(payment_date) ASC")
      else
        # Generic fallback for SQLite/MySQL
        rows = base_scope
          .select("normalized_vehicle_number,
                   MIN(vehicle_number) AS vehicle_number,
                   MIN(payment_date)   AS earliest_payment_date,
                   SUM(amount_cents)   AS total_amount_cents,
                   MIN(payment_ref)    AS payment_ref,
                   MAX(CASE WHEN matched THEN 1 ELSE 0 END) AS any_matched")
          .group("normalized_vehicle_number")
          .order("MIN(payment_date) ASC")
      end

      @tax_payments = rows.page(params[:page]).per(20)
      nvns = @tax_payments.map { |r| r.normalized_vehicle_number }.compact.uniq
    else
      @tax_payments = base_scope.page(params[:page]).per(20)
      nvns = @tax_payments.pluck(:normalized_vehicle_number).compact.uniq
    end

    # Lookup arrear info for displayed vehicles
    @arrear_map = ArrearCase
                    .where(normalized_vehicle_number: nvns)
                    .pluck(:normalized_vehicle_number, :tax_arrear_from, :first_notice_total_cents)
                    .to_h { |nvn, from, cents| [nvn, { tax_arrear_from: from, total_tax_due: (cents.to_i / 100.0) }] }
  end

  # GET /tax_payments/sample_template.csv
  def sample_template
    csv = CSV.generate(headers: true) do |out|
      out << [
        "Receipt Date","Registration No.","Receipt No.",
        "Tax in (Rs.)","Exempted in (Rs.)","Rebate in (Rs.)","Interest in (Rs.)",
        "Tax1 in (Rs.)","Tax2 in (Rs.)","Tax Adjustment in (Rs.)",
        "Surcharge in (Rs.)","Penalty in (Rs.)","Total in (Rs.)"
      ]
    end
    send_data csv, filename: "tax_paid_template.csv", type: "text/csv"
  end

  # GET /tax_payments/export_matched.csv
  def export_matched
    base_scope = TaxPayment.where(matched: true)
    base_scope = base_scope.ransack(params[:q]).result if params[:q].present?

    adapter = ActiveRecord::Base.connection.adapter_name.to_s.downcase
    earliest_scope =
      if adapter.include?("postgres")
        base_scope
          .select("DISTINCT ON (normalized_vehicle_number) *")
          .order("normalized_vehicle_number, payment_date ASC, id ASC")
      else
        ids = base_scope
                .to_a
                .group_by(&:normalized_vehicle_number)
                .map { |_, rows| rows.min_by { |tp| [tp.payment_date || Date.new(9999,1,1), tp.id] }.id }
        TaxPayment.where(id: ids)
      end

    nvns = earliest_scope.pluck(:normalized_vehicle_number).compact.uniq
    arrear_map = ArrearCase
                   .where(normalized_vehicle_number: nvns)
                   .pluck(:normalized_vehicle_number, :tax_arrear_from, :first_notice_total_cents)
                   .to_h { |nvn, tax_from, total_cents| [nvn, { tax_arrear_from: tax_from, total_tax_due: (total_cents.to_i / 100.0) }] }

    csv = CSV.generate(headers: true) do |out|
      out << %w[Vehicle\ No Payment\ Date Tax\ Paid\ Amount Payment\ Ref Matched Tax\ Arrear\ From Total\ Tax\ Due]
      earliest_scope.find_each do |tp|
        a = arrear_map[tp.normalized_vehicle_number] || {}
        out << [
          tp.vehicle_number,
          tp.payment_date,
          (tp.amount_cents.to_i / 100.0),
          tp.payment_ref,
          "Yes",
          a[:tax_arrear_from],
          a[:total_tax_due]
        ]
      end
    end

    send_data csv, filename: "matched_sheet-#{Date.today}.csv", type: "text/csv"
  end

  # GET /tax_payments/export.csv
  def export
    scope   = TaxPayment.ransack(params[:q]).result.order(payment_date: :desc)
    adapter = ActiveRecord::Base.connection.adapter_name.to_s.downcase
    grouped = (params[:group] == "vehicle")

    if grouped
      rel =
        if adapter.include?("postgres")
          scope
            .select("normalized_vehicle_number,
                     MIN(vehicle_number) AS vehicle_number,
                     MIN(payment_date)   AS earliest_payment_date,
                     SUM(amount_cents)   AS total_amount_cents,
                     MIN(payment_ref)    AS payment_ref,
                     BOOL_OR(matched)    AS any_matched")
            .group("normalized_vehicle_number")
            .order("MIN(payment_date) ASC")
        else
          scope
            .select("normalized_vehicle_number,
                     MIN(vehicle_number) AS vehicle_number,
                     MIN(payment_date)   AS earliest_payment_date,
                     SUM(amount_cents)   AS total_amount_cents,
                     MIN(payment_ref)    AS payment_ref,
                     MAX(CASE WHEN matched THEN 1 ELSE 0 END) AS any_matched")
            .group("normalized_vehicle_number")
            .order("MIN(payment_date) ASC")
        end

      nvns = rel.pluck(:normalized_vehicle_number).compact.uniq
      arrear_map = ArrearCase
                     .where(normalized_vehicle_number: nvns)
                     .pluck(:normalized_vehicle_number, :tax_arrear_from, :first_notice_total_cents)
                     .to_h { |nvn, from, cents| [nvn, { tax_arrear_from: from, total_tax_due: (cents.to_i / 100.0) }] }

      csv = CSV.generate(headers: true) do |out|
        out << [
          "Vehicle No",
          "Earliest Receipt Date",
          "Total Amount (₹)",
          "Any Receipt No.",
          "Any Matched?",
          "Tax Arrear From",
          "Total Tax Due (Arrear)"
        ]

        rel.find_each do |r|
          extra = arrear_map[r.normalized_vehicle_number] || {}
          any_matched_text =
            if adapter.include?("postgres")
              r.any_matched ? "Yes" : "No"
            else
              r.any_matched.to_i > 0 ? "Yes" : "No"
            end

          out << [
            r.vehicle_number,
            r.earliest_payment_date,
            (r.total_amount_cents.to_i / 100.0),
            r.payment_ref,
            any_matched_text,
            extra[:tax_arrear_from],
            extra[:total_tax_due]
          ]
        end
      end
    else
      nvns = scope.pluck(:normalized_vehicle_number).compact.uniq
      arrear_map = ArrearCase
                     .where(normalized_vehicle_number: nvns)
                     .pluck(:normalized_vehicle_number, :tax_arrear_from, :first_notice_total_cents)
                     .to_h { |nvn, from, cents| [nvn, { tax_arrear_from: from, total_tax_due: (cents.to_i / 100.0) }] }

      csv = CSV.generate(headers: true) do |out|
        out << [
          "Vehicle No",
          "Receipt Date",
          "Total from Upload (₹)",
          "Receipt No.",
          "Matched?",
          "File",
          "Tax Arrear From",
          "Total Tax Due (Arrear)"
        ]
        scope.find_each do |tp|
          extra = arrear_map[tp.normalized_vehicle_number] || {}
          out << [
            tp.vehicle_number,
            tp.payment_date,
            (tp.amount_cents.to_i / 100.0),
            tp.payment_ref,
            (tp.matched ? "Yes" : "No"),
            tp.source_file,
            extra[:tax_arrear_from],
            extra[:total_tax_due]
          ]
        end
      end
    end

    send_data csv, filename: "tax_payments-#{Date.today}.csv", type: "text/csv"
  end

  # GET  /tax_payments/imports   -> show upload form
  # POST /tax_payments/imports   -> process the file
  def imports
    return unless request.post?

    if params[:file].blank?
      return redirect_to imports_tax_payments_path, alert: "Please choose an Excel file (.xlsx/.xls)"
    end

    # 👉 This calls TaxPaidImportService which is where you should replace
    # row-by-row create! with the upsert_all + fingerprint code I gave you.
    result = TaxPaidImportService.new(params[:file]).call

    msg = "Imported #{result[:created]} rows. Applied earliest-only matching for #{result[:matched]} vehicle(s)."

    respond_to do |format|
      format.html         { redirect_to tax_payments_path, notice: msg }
      format.turbo_stream { redirect_to tax_payments_path, notice: msg }
    end
  rescue => e
    Rails.logger.error("[TaxPayments#imports] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    redirect_to imports_tax_payments_path, alert: "Import failed: #{e.message}"
  end

  private
  # def ensure_creator!
  #   unless current_user&.admin? || current_user&.creator?
  #     redirect_to tax_payments_path, alert: "You are not authorized for this action."
  #   end
  # end
end
