Rails.application.routes.draw do
  devise_for :users

  root "dashboard#index"
  get "up" => "rails/health#show", as: :rails_health_check

  resources :arrear_cases do
    collection do
      get  :imports
      post :imports
      get  :export
      get  :sample_template   # ← notice import template
    end
  end

  resources :tax_payments, only: [:index] do
    collection do
      get  :imports
      post :imports
      get  :sample_template   # ← tax-paid import template
    end
  end
end
