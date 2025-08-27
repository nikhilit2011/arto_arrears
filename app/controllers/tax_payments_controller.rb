# app/controllers/tax_payments_controller.rb
require "csv"

class TaxPaymentsController < ApplicationController
  # Uncomment to restrict to creators/admins
  # before_action :ensure_creator!, only: [:imports]

  def index
    @q = TaxPayment.ransack(params[:q])
    @tax_payments = @q.result.order(payment_date: :desc).page(params[:page]).per(20)
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

  # GET  /tax_payments/imports   -> show upload form
  # POST /tax_payments/imports   -> process the file
  def imports
    return unless request.post?

    if params[:file].blank?
      return redirect_to imports_tax_payments_path, alert: "Please choose an Excel file (.xlsx/.xls)"
    end

    result = TaxPaidImportService.new(params[:file]).call

    respond_to do |format|
      msg = "Imported #{result[:created]} rows (matched #{result[:matched]} to Notice DB)."
      format.html        { redirect_to tax_payments_path, notice: msg }
      format.turbo_stream { redirect_to tax_payments_path, notice: msg }
    end
  rescue => e
    Rails.logger.error("[TaxPayments#imports] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    redirect_to imports_tax_payments_path, alert: "Import failed: #{e.message}"
  end

  private

  # Optional role guard
  # def ensure_creator!
  #   unless current_user&.admin? || current_user&.creator?
  #     redirect_to tax_payments_path, alert: "You are not authorized for this action."
  #   end
  # end
end
