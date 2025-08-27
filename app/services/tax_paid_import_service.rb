# frozen_string_literal: true
class TaxPaidImportService
  require "roo"

  HEADER_MAP = {
    vehicle: [/^registration\s*no\.?$/i, /vehicle/i, /regn/i, /registration/i],    # REQUIRED
    date:    [/^receipt\s*date$/i, /paid.*date/i, /payment.*date/i, /\bdate\b/i],
    amount:  [/^total.*\(rs\.\)$/i, /^total\s*in\s*\(rs\.\)$/i, /^total$/i, /amount/i],
    ref:     [/^receipt\s*no\.?$/i, /ref/i, /challan/i, /utr/i]
  }.freeze

  POSITIVE_PARTS = {
    tax:       [/^tax\s*in\s*\(rs\.\)$/i, /^tax$/i],
    tax1:      [/^tax1\s*in\s*\(rs\.\)$/i, /^tax1$/i],
    tax2:      [/^tax2\s*in\s*\(rs\.\)$/i, /^tax2$/i],
    interest:  [/^interest\s*in\s*\(rs\.\)$/i, /^interest$/i],
    surcharge: [/^surcharge\s*in\s*\(rs\.\)$/i, /^surcharge$/i],
    penalty:   [/^penalty\s*in\s*\(rs\.\)$/i, /^penalty$/i],
    adjust:    [/^tax\s*adjustment\s*in\s*\(rs\.\)$/i, /^tax\s*adjustment$/i]
  }.freeze

  NEGATIVE_PARTS = {
    exempted: [/^exempted\s*in\s*\(rs\.\)$/i, /^exempted$/i],
    rebate:   [/^rebate\s*in\s*\(rs\.\)$/i,   /^rebate$/i]
  }.freeze

  def initialize(file); @file = file; end

  def call
    x = open_spreadsheet(@file); s = x.sheet(0)
    header = s.row(1).map { |h| h.to_s.strip }
    idx = index_headers!(header)
    parts_idx = index_parts(header)

    created = 0; matched = 0

    (2..s.last_row).each do |i|
      row   = s.row(i)
      raw_v = cell(row, idx[:vehicle]).to_s.strip
      next if raw_v.blank?

      norm   = normalize_vehicle(raw_v)
      pdate  = parse_date(cell(row, idx[:date]))
      pref   = cell(row, idx[:ref]).to_s.strip.presence
      amount = idx[:amount] ? money(cell(row, idx[:amount])) : compute_amount_cents(row, parts_idx)
      fname  = filename_for(@file)

      tp = TaxPayment.create!(
        vehicle_number: raw_v,
        normalized_vehicle_number: norm,
        payment_date: pdate,
        amount_cents: amount,
        payment_ref: pref,
        source_file: fname,
        matched: false
      )
      created += 1

      if (ac = ArrearCase.find_by(normalized_vehicle_number: norm))
        ac.tax_paid_status = true
        ac.tax_paid_amount_cents = ac.tax_paid_amount_cents.to_i + amount.to_i
        ac.tax_paid_date = [ac.tax_paid_date, pdate].compact.max
        ac.save!

        tp.update!(matched: true)
        matched += 1
      end
    end

    { created: created, matched: matched }
  end

  private

  def open_spreadsheet(upload)
    path = upload.respond_to?(:path) ? upload.path : upload.tempfile.path
    upload.tempfile.rewind if upload.respond_to?(:tempfile) && upload.tempfile&.respond_to?(:rewind)
    ext = File.extname(filename_for(upload)).delete(".").downcase
    ext = "xlsx" if ext.blank?
    Roo::Spreadsheet.open(path, extension: ext)
  end

  def filename_for(upload)
    upload.respond_to?(:original_filename) ? upload.original_filename : File.basename(upload.path)
  end

  def index_headers!(header)
    idx = {}
    HEADER_MAP.each do |key, pats|
      i = header.index { |h| pats.any? { |rx| h =~ rx } }
      raise "Missing required Vehicle column" if key == :vehicle && i.nil?
      idx[key] = i
    end; idx
  end

  def index_parts(header)
    {
      positives: POSITIVE_PARTS.transform_values { |pats| header.index { |h| pats.any? { |rx| h =~ rx } } },
      negatives: NEGATIVE_PARTS.transform_values { |pats| header.index { |h| pats.any? { |rx| h =~ rx } } }
    }
  end

  def cell(row, i); i.nil? ? nil : row[i]; end

  def normalize_vehicle(v); v.to_s.upcase.gsub(/[^A-Z0-9]/, ""); end

  def parse_date(v)
    return nil if v.blank?
    return v if v.is_a?(Date)
    return v.to_date if v.respond_to?(:to_date) rescue nil
    Date.parse(v.to_s) rescue nil
  end

  def money(v)
    return 0 if v.nil? || (v.is_a?(String) && v.strip.empty?)
    n = v.is_a?(Numeric) ? v.to_f : v.to_s.gsub(/[^\d\.\-]/, "").to_f
    (n * 100).round
  end

  def compute_amount_cents(row, parts_idx)
    pos = parts_idx[:positives].values.compact.sum { |i| money(cell(row, i)) }
    neg = parts_idx[:negatives].values.compact.sum { |i| money(cell(row, i)) }
    pos - neg
  end
end
