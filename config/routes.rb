Rails.application.routes.draw do
  devise_for :users

  root "dashboard#index"
  get "up" => "rails/health#show", as: :rails_health_check
  
  get  "/reconciliation", to: "reconciliations#index"

  resources :arrear_cases do
    collection do
      get  :imports
      post :imports
      get  :export
      get  :sample_template
      delete :bulk_destroy
      delete :destroy_all 
      
    end
  end

  resources :tax_payments, only: [:index] do
    collection do
      get  :imports
      post :imports
      get  :sample_template
      get  :export_matched
      get  :export
    end
  end

 
end
