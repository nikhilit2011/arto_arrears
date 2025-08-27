class AddVehicleCategoryAndPraiseToFeedbacks < ActiveRecord::Migration[7.1]
  def change
    add_column :feedbacks, :vehicle_category, :string
    add_column :feedbacks, :praise_note, :text
  end
end
