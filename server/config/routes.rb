Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :accounts, only: [] do
    collection do
      get :recently_paid
    end
    member do
      get :ledger
      get :activity
    end
  end
end
