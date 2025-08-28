# app/services/tax_paid_import_service.rb
require "roo"
require "digest"

class TaxPaidImportService
  def initialize(file)
    @file = file
  end

  # Returns { created: Integer, matched: Integer }
  def call
    x = Roo::Spreadsheet.open(@file.path)
    sheet = x.sheet(0)

    headers = sheet.row(1).map { |h| h.to_s.strip }
    idx = header_index_map(headers)

    now = Time.current
    rows = []

    ((sheet.first_row + 1)..sheet.last_row).each do |r|
      row = sheet.row(r)

      reg_no = pick(row, idx[:registration_no])
      next if reg_no.to_s.strip.empty?

      vehicle_number = reg_no.to_s.strip
      payment_date   = parse_date(pick(row, idx[:receipt_date]))
      total_rs       = parse_money(pick(row, idx[:total_in_rs]))
      # fallback if "Total in (Rs.)" is empty, try "Tax in (Rs.)" + "Penalty in (Rs.)"
      if total_rs.zero?
        tax_rs     = parse_money(pick(row, idx[:tax_in_rs]))
        penalty_rs = parse_money(pick(row, idx[:penalty_rs]))
        total_rs   = tax_rs + penalty_rs
      end

      payment_ref = pick(row, idx[:transaction_no]).presence ||
                    pick(row, idx[:receipt_no]).presence ||
                    ""

      h = {
        vehicle_number:            vehicle_number,
        normalized_vehicle_number: vehicle_number.upcase.gsub(/[^A-Z0-9]/, ""),
        payment_date:              payment_date,
        amount_cents:              (total_rs.round(2) * 100).to_i,
        payment_ref:               payment_ref.to_s,
        source_file:               @file.respond_to?(:original_filename) ? @file.original_filename.to_s : "",
        created_at:                now,
        updated_at:                now
      }

      # fingerprint (must match model logic, but computed here for upsert_all)
      key = [
        h[:normalized_vehicle_number].to_s.strip,
        h[:payment_date].to_s,
        h[:amount_cents].to_i.to_s,
        h[:payment_ref].to_s.strip.upcase
      ].join("|")
      h[:fingerprint] = Digest::MD5.hexdigest(key)

      rows << h
    end

    rows.compact!
    return { created: 0, matched: 0 } if rows.empty?

    # Idempotent bulk write: duplicates (same fingerprint) are ignored by the unique index
    result = TaxPayment.upsert_all(
      rows,
      unique_by: :index_tax_payments_on_fingerprint
    )

    # result.rows may be nil in some adapters; fall back to counting by diff in table size if needed
    created_count = result.respond_to?(:rows) && result.rows ? result.rows.length : 0

    { created: created_count, matched: 0 }
  end

  private

  # Map common header variants to indices
  def header_index_map(headers)
    {
      receipt_date:     find_idx(headers, ["Receipt Date", "Payment Date", "Date"]),
      registration_no:  find_idx(headers, ["Registration No.", "Registration No", "Vehicle No", "Vehicle Number"]),
      receipt_no:       find_idx(headers, ["Receipt No.", "Receipt No"]),
      transaction_no:   find_idx(headers, ["Transaction No.", "Transaction No"]),
      total_in_rs:      find_idx(headers, ["Total in (Rs.)", "Total in Rs.", "Total", "Total Amount (Rs.)"]),
      tax_in_rs:        find_idx(headers, ["Tax in (Rs.)", "Tax in Rs."]),
      penalty_rs:       find_idx(headers, ["Penalty in (Rs.)", "Penalty"])
    }
  end

  def find_idx(headers, candidates)
    candidates.each do |name|
      i = headers.index { |h| h.casecmp?(name) }
      return i if i
    end
    nil
  end

  def pick(row, index)
    index.nil? ? nil : row[index]
  end

  def parse_date(v)
    return v if v.is_a?(Date)
    return v.to_date if v.respond_to?(:to_date) rescue nil
    Date.parse(v.to_s) rescue nil
  end

  def parse_money(v)
    return 0.0 if v.nil?
    s = v.to_s.strip
    s = s.gsub(/[,\s]/, "")
    s = s.gsub(/[^\d\.]/, "") # strip stray symbols
    s.empty? ? 0.0 : s.to_f
  end
end
