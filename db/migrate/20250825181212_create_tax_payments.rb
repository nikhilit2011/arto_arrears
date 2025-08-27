class CreateTaxPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :tax_payments do |t|
      t.string :vehicle_number
      t.string :normalized_vehicle_number
      t.date :payment_date
      t.bigint :amount_cents
      t.string :payment_ref
      t.string :source_file
      t.boolean :matched

      t.timestamps
    end
    add_index :tax_payments, :normalized_vehicle_number
  end
end
