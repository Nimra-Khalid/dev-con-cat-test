Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  Rails.application.routes.draw do

    # Authentication
    post "/login", to: "sessions#create"
    delete "/logout", to: "sessions#destroy"
    get "/me", to: "sessions#show"  

    post "/visit", to: "ingestion#visit"
    post "/leads", to: "ingestion#create_lead"

    get "/leads/:lead_id/activity",
    to: "ingestion#activity"

    get "/crm/leads", to: "leads#index"
    get "/crm/leads/:id", to: "leads#show"

    get "/certificates/:public_id",
    to: "certificates#show"

    get "/login-page", to: "dashboard#login"
    get "/dashboard", to: "dashboard#index"
    get "/crm", to: "dashboard#crm"
    get "/crm/lead/:id", to: "dashboard#lead", as: :crm_lead_page

    get "/pixels", to: "pixels#index"
    post "/pixels", to: "pixels#create"
    get "/pixels/:id", to: "pixels#show"
    patch "/pixels/:id", to: "pixels#update"

    get "/pixels-page", to: "dashboard#pixels"

    get "/admin/accounts", to: "admin/accounts#index"
    get "/admin", to: "dashboard#admin"
    end
end
