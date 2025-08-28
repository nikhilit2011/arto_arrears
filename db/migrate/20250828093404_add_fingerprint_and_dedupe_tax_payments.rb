# db/migrate/20250828_add_fingerprint_and_dedupe_tax_payments.rb
class AddFingerprintAndDedupeTaxPayments < ActiveRecord::Migration[7.1]
  def up
    # 1) New column
    add_column :tax_payments, :fingerprint, :string

    # 2) Backfill fingerprints for existing rows
    # Fingerprint uses ONLY stable identity fields:
    #   normalized_vehicle_number | payment_date | amount_cents | UPPER(payment_ref)
    execute <<~SQL
      UPDATE tax_payments
      SET fingerprint = md5(
        COALESCE(normalized_vehicle_number,'') || '|' ||
        COALESCE(payment_date::text,'')       || '|' ||
        COALESCE(amount_cents::text,'')       || '|' ||
        UPPER(COALESCE(payment_ref,''))
      )
      WHERE fingerprint IS NULL;
    SQL

    # 3) Deduplicate existing rows: keep the lowest id per fingerprint
    execute <<~SQL
      WITH ranked AS (
        SELECT id, fingerprint,
               ROW_NUMBER() OVER (PARTITION BY fingerprint ORDER BY id) AS rn
        FROM tax_payments
        WHERE fingerprint IS NOT NULL
      )
      DELETE FROM tax_payments tp
      USING ranked r
      WHERE tp.id = r.id
        AND r.rn > 1;
    SQL

    # 4) Indexes
    add_index :tax_payments, :fingerprint, unique: true, name: "index_tax_payments_on_fingerprint"
    add_index :tax_payments, :normalized_vehicle_number, name: "index_tax_payments_on_nvn"
    add_index :tax_payments, :payment_date, name: "index_tax_payments_on_payment_date"

    # 5) Enforce NOT NULL going forward
    change_column_null :tax_payments, :fingerprint, false
  end

  def down
    remove_index :tax_payments, name: "index_tax_payments_on_payment_date"
    remove_index :tax_payments, name: "index_tax_payments_on_nvn"
    remove_index :tax_payments, name: "index_tax_payments_on_fingerprint"
    remove_column :tax_payments, :fingerprint
  end
end
