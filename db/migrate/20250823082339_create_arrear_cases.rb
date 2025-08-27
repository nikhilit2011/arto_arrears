class CreateArrearCases < ActiveRecord::Migration[7.1]
  def change
    create_table :arrear_cases do |t|
      t.string :vehicle_number
      t.string :normalized_vehicle_number
      t.string :vehicle_type
      t.date :tax_arrear_from
      t.date :first_notice_date
      t.bigint :first_notice_tax_cents
      t.bigint :first_notice_penalty_cents
      t.bigint :first_notice_total_cents
      t.date :second_notice_date
      t.bigint :second_notice_tax_cents
      t.bigint :second_notice_penalty_cents
      t.bigint :second_notice_total_cents
      t.date :recovery_challan_date
      t.bigint :recovery_challan_tax_cents
      t.bigint :recovery_challan_penalty_cents
      t.boolean :tax_paid_status
      t.date :tax_paid_date
      t.bigint :tax_paid_amount_cents
      t.text :remarks

      t.timestamps
    end
    add_index :arrear_cases, :normalized_vehicle_number
  end
end
