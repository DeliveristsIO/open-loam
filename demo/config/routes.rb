Rails.application.routes.draw do
  namespace :admin do
    resources :damage_reports
    resources :equipment
    root "dashboard#index"
    resource :session, only: %i[new create destroy] do
      post :select_tenant
    end
    resources :field_definitions, only: %i[index new create destroy]
    resources :notifications, only: %i[index] do
      post :mark_read, on: :member
    end
    resources :webhook_endpoints, only: %i[index new create destroy]
    resources :api_tokens, only: %i[index create destroy]
    resources :comments, only: %i[create]
  end

  namespace :api do
    resources :damage_reports, defaults: { format: :json }
    resources :equipment, defaults: { format: :json }
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
