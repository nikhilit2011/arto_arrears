# frozen_string_literal: true
class NoticeImportService
  require "roo"

  HEADER_MAP = {
    vehicle:          [/vehicle/i, /regn/i, /registration/i],          # REQUIRED
    type:             [/type/i],
    arrear_from:      [/arrear/i],
    first_date:       [/first.*date/i],
    first_tax:        [/first.*tax/i],
    first_penalty:    [/first.*penalty/i],
    first_total:      [/first.*total/i],
    second_date:      [/second.*date/i],
    second_tax:       [/second.*tax/i],
    second_penalty:   [/second.*penalty/i],
    second_total:     [/second.*total/i],
    recovery_date:    [/recovery.*date/i],
    recovery_tax:     [/recovery.*tax/i],
    recovery_penalty: [/recovery.*penalty/i],
    remarks:          [/remarks?/i]
  }.freeze

  def initialize(file)
    @file = file # ActionDispatch::Http::UploadedFile OR File
  end

  def call
    x = open_spreadsheet(@file)
    s = x.sheet(0)

    header = s.row(1).map { |h| h.to_s.strip }
    idx = index_headers!(header)

    created = 0
    updated = 0

    (2..s.last_row).each do |i|
      row   = s.row(i)
      raw_v = safe_cell(row, idx[:vehicle]).to_s.strip
      next if raw_v.blank?

      norm  = normalize_vehicle(raw_v)

      attrs = {
        vehicle_number:                 raw_v,
        normalized_vehicle_number:      norm,
        vehicle_type:                   safe_cell(row, idx[:type]),
        tax_arrear_from:                parse_date(safe_cell(row, idx[:arrear_from])),
        first_notice_date:              parse_date(safe_cell(row, idx[:first_date])),
        first_notice_tax_cents:         money(safe_cell(row, idx[:first_tax])),
        first_notice_penalty_cents:     money(safe_cell(row, idx[:first_penalty])),
        first_notice_total_cents:       money(safe_cell(row, idx[:first_total])),
        second_notice_date:             parse_date(safe_cell(row, idx[:second_date])),
        second_notice_tax_cents:        money(safe_cell(row, idx[:second_tax])),
        second_notice_penalty_cents:    money(safe_cell(row, idx[:second_penalty])),
        second_notice_total_cents:      money(safe_cell(row, idx[:second_total])),
        recovery_challan_date:          parse_date(safe_cell(row, idx[:recovery_date])),
        recovery_challan_tax_cents:     money(safe_cell(row, idx[:recovery_tax])),
        recovery_challan_penalty_cents: money(safe_cell(row, idx[:recovery_penalty])),
        remarks:                        safe_cell(row, idx[:remarks])
      }.compact # keep 0 values, drop nils

      record = ArrearCase.find_or_initialize_by(normalized_vehicle_number: norm)
      if record.new_record?
        record.assign_attributes(attrs)
        record.save!
        created += 1
      else
        record.update!(attrs)
        updated += 1
      end
    end

    { created: created, updated: updated }
  end

  private

  # --- IO/open helpers ---

  def open_spreadsheet(upload)
    # Prefer a real filesystem path; Roo handles xlsx/xls/csv by extension
    path = if upload.respond_to?(:path) && upload.path
             upload.path
           elsif upload.respond_to?(:tempfile) && upload.tempfile
             upload.tempfile.path
           else
             raise "Unsupported upload type"
           end

    filename  = upload.respond_to?(:original_filename) ? upload.original_filename : File.basename(path)
    ext = File.extname(filename).delete(".").downcase
    ext = "xlsx" if ext.blank? # sensible default

    # Rewind Tempfile just in case
    upload.tempfile.rewind if upload.respond_to?(:tempfile) && upload.tempfile && upload.tempfile.respond_to?(:rewind)

    Roo::Spreadsheet.open(path, extension: ext)
  end

  # Find header indexes; vehicle is required, others optional
  def index_headers!(header_row)
    idx = {}
    HEADER_MAP.each do |key, patterns|
      i = header_row.index { |h| patterns.any? { |rx| h =~ rx } }
      if key == :vehicle && i.nil?
        raise "Missing required column for Vehicle (expected one of: #{patterns.map(&:inspect).join(', ')})"
      end
      idx[key] = i # can be nil for optional columns
    end
    idx
  end

  # Safe cell fetch when index can be nil
  def safe_cell(row, index)
    index.nil? ? nil : row[index]
  end

  # --- parsing helpers ---

  def normalize_vehicle(v)
    v.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  def parse_date(v)
    return nil if v.blank?
    return v if v.is_a?(Date)
    return v.to_date if v.respond_to?(:to_date) rescue nil
    Date.parse(v.to_s)
  rescue
    nil
  end

  def money(v)
    return nil if v.nil? || (v.is_a?(String) && v.strip.empty?)
    # Strip currency symbols, commas, spaces etc., keep digits, dot, minus
    numeric = v.is_a?(Numeric) ? v.to_f : v.to_s.gsub(/[^\d\.\-]/, "").to_f
    (numeric * 100).round
  end
end
