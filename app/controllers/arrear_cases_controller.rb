# app/controllers/arrear_cases_controller.rb
require "csv"

class ArrearCasesController < ApplicationController
  before_action :set_arrear_case, only: [:show, :edit, :update, :destroy]
  # Uncomment this block to restrict create/edit/import/export to creator/admin roles
  # before_action :ensure_creator!, only: [:new, :create, :edit, :update, :destroy, :imports, :export]

  # GET /arrear_cases
  def index
    @q = ArrearCase.ransack(params[:q])
    @arrear_cases = @q.result.order(created_at: :desc).page(params[:page]).per(20)
  end

  # GET /arrear_cases/:id
  def show; end

  # GET /arrear_cases/new
  def new
    @arrear_case = ArrearCase.new
  end

  # POST /arrear_cases
  def create
    @arrear_case = ArrearCase.new(arrear_case_params)
    if @arrear_case.save
      redirect_to arrear_cases_path, notice: "Record created successfully."
    else
      flash.now[:alert] = @arrear_case.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  # GET /arrear_cases/:id/edit
  def edit; end

  # PATCH/PUT /arrear_cases/:id
  def update
    if @arrear_case.update(arrear_case_params)
      redirect_to arrear_cases_path, notice: "Record updated successfully."
    else
      flash.now[:alert] = @arrear_case.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy_all
    unless current_user&.admin? || current_user&.creator?
      redirect_to arrear_cases_path, alert: "You are not authorized for this action." and return
    end

    total = ArrearCase.count
    # Use delete_all for speed (skips callbacks). Use destroy_all if you need callbacks.
    ArrearCase.delete_all

    redirect_to arrear_cases_path, notice: "#{total} notice#{'s' unless total == 1} deleted permanently."
  end
  

  # DELETE /arrear_cases/:id
  def destroy
    @arrear_case.destroy
    redirect_to arrear_cases_path, notice: "Record deleted successfully."
  end

  # DELETE /arrear_cases/bulk_destroy
  def bulk_destroy
    ids = Array(params[:ids] || params[:arrear_case_ids]).map(&:to_i).uniq
    if ids.empty?
      redirect_to arrear_cases_path, alert: "No records selected."
    else
      destroyed = ArrearCase.where(id: ids).destroy_all.length
      redirect_to arrear_cases_path, notice: "#{destroyed} record#{'s' unless destroyed == 1} deleted successfully."
    end
  end

  # ========= Imports =========
  # GET  /arrear_cases/imports  -> show upload form
  # POST /arrear_cases/imports  -> handle Excel upload
  def imports
    return unless request.post?

    file = import_file_param
    unless file
      return redirect_to imports_arrear_cases_path, alert: "Please choose an Excel file (.xlsx/.xls)"
    end

    result = NoticeImportService.new(file).call

    respond_to do |format|
      format.html { redirect_to arrear_cases_path, notice: "Import complete: #{result[:created]} new, #{result[:updated]} updated." }
      format.turbo_stream { redirect_to arrear_cases_path, notice: "Import complete: #{result[:created]} new, #{result[:updated]} updated." }
    end
  rescue => e
    Rails.logger.error("[ArrearCases#imports] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    redirect_to imports_arrear_cases_path, alert: "Import failed: #{e.message}"
  end

  # ========= Export =========
  # GET /arrear_cases/export -> download CSV snapshot (amounts in rupees)
  def export
    csv = CSV.generate(headers: true) do |out|
      out << [
        "Vehicle No","Vehicle Type","Tax Arrear From",
        "First Notice Date","First Notice Tax","First Notice Penalty","First Notice Total",
        "Second Notice Date","Second Notice Tax","Second Notice Penalty","Second Notice Total",
        "Recovery Challan Date","Recovery Challan Tax","Recovery Challan Penalty",
        "Tax Paid Status","Tax Paid Date","Tax Paid Amount","Remarks"
      ]

      ArrearCase.find_each do |r|
        out << [
          r.vehicle_number, r.vehicle_type, r.tax_arrear_from,
          r.first_notice_date,  r.first_notice_tax_cents.to_i / 100.0,  r.first_notice_penalty_cents.to_i / 100.0,  r.first_notice_total_cents.to_i / 100.0,
          r.second_notice_date, r.second_notice_tax_cents.to_i / 100.0, r.second_notice_penalty_cents.to_i / 100.0, r.second_notice_total_cents.to_i / 100.0,
          r.recovery_challan_date, r.recovery_challan_tax_cents.to_i / 100.0, r.recovery_challan_penalty_cents.to_i / 100.0,
          (r.tax_paid_status ? "Yes" : "No"), r.tax_paid_date, r.tax_paid_amount_cents.to_i / 100.0, r.remarks
        ]
      end
    end

    send_data csv, filename: "arrear_cases-#{Date.today}.csv", type: "text/csv"
  end

  private

  def set_arrear_case
    @arrear_case = ArrearCase.find(params[:id])
  end

  def arrear_case_params
    params.require(:arrear_case).permit(
      :vehicle_number, :vehicle_type, :tax_arrear_from,
      :first_notice_date, :first_notice_tax_cents, :first_notice_penalty_cents, :first_notice_total_cents,
      :second_notice_date, :second_notice_tax_cents, :second_notice_penalty_cents, :second_notice_total_cents,
      :recovery_challan_date, :recovery_challan_tax_cents, :recovery_challan_penalty_cents,
      :tax_paid_status, :tax_paid_date, :tax_paid_amount_cents, :remarks
    )
  end
  
  def sample_template
    csv = CSV.generate(headers: true) do |out|
      out << [
        "Vehicle No","Vehicle Type","Tax Arrear From",
        "First Notice Date","First Notice Tax","First Notice Penalty","First Notice Total",
        "Second Notice Date","Second Notice Tax","Second Notice Penalty","Second Notice Total",
        "Recovery Challan Date","Recovery Challan Tax","Recovery Challan Penalty",
        "Remarks"
      ]
      # (no data rows; this is just a header template)
    end
    send_data csv, filename: "notice_import_template.csv", type: "text/csv"
  end

  # Accept both file param keys: :file (file_field_tag) or nested under :arrear_case[:file]
  def import_file_param
    params[:file] || params.dig(:arrear_case, :file)
  end

  # Uncomment to enforce role-based access for mutations/import/export
  # def ensure_creator!
  #   unless current_user&.admin? || current_user&.creator?
  #     redirect_to arrear_cases_path, alert: "You are not authorized for this action."
  #   end
  # end
end
