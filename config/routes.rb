Rails.application.routes.draw do
  devise_for :users

  root "dashboard#index"
  get "up" => "rails/health#show", as: :rails_health_check

  resources :arrear_cases do
    collection do
      get  :imports
      post :imports
      get  :export
      get  :sample_template
    end
  end

  resources :tax_payments, only: [:index] do
    collection do
      get  :imports
      post :imports
      get  :sample_template
    end
  end

  # === TEMP ADMIN CREATOR ROUTE (remove after first use) ===
  get "/create_admin", to: proc { |env|
    # hardcoded one-time credentials
    email    = "admin@example.com"
    password = "supersecurepassword"

    user = User.find_or_initialize_by(email: email)
    user.password = password
    user.password_confirmation = password
    user.role = "admin" if user.respond_to?(:role=)
    user.save!

    [
      200,
      { "Content-Type" => "text/plain" },
      ["Admin created/updated. Email: #{email}, Password: #{password}"]
    ]
  }
  # === END TEMP ROUTE ===
end
