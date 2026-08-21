Rails.application.routes.draw do
  namespace :admin do
    resources :customers do
      get :deleted, on: :collection
      patch :restore, on: :member
    end
    resources :damage_reports do
      get :deleted, on: :collection
      patch :restore, on: :member
    end
    resources :equipment do
      get :deleted, on: :collection
      patch :restore, on: :member
      post :propose_price, on: :member  # an "AI-proposed" change, staged for approval
      get :export, on: :collection      # CSV of the current filtered view
      post :bulk, on: :collection       # datatable bulk actions on selected rows
    end
    resources :imports, only: %i[new create] do  # generic CSV importer (by entity_type)
      collection do
        post :preview
        post :download_errors
      end
    end
    root "dashboard#index"
    resource :session, only: %i[new create destroy] do
      get :mfa_challenge
      post :mfa_verify
      post :select_tenant
      post :sso_start     # home-realm discovery: email -> tenant IdP
      get  :sso_callback  # the IdP redirect target
    end
    resource :mfa, only: %i[show new create destroy], controller: "mfa"  # a user's own two-factor setup
    resource :sudo, only: %i[new create], controller: "sudo"             # step-up re-challenge
    resources :pending_actions, only: %i[index] do                       # the approval queue
      member do
        post :approve
        post :reject
      end
    end
    resources :perspectives, only: %i[index create update destroy] do    # saved table views
      post :set_default, on: :member
    end
    # Manager take-over of an advisory edit lock (lockable_type + lockable_id params).
    delete "record_lock", to: "record_locks#destroy", as: :record_lock
    get "events/stream", to: "events#stream", as: :events_stream  # SSE push (Loam::EventStream)
    resources :business_rules, only: %i[index new create edit update destroy]  # when/then rules
    resources :sso_providers, only: %i[index new create edit update destroy]   # per-tenant OIDC config
    resources :dictionaries, only: %i[index new create edit update destroy] do # managed lookup lists
      resources :entries, only: %i[create update destroy], controller: "dictionary_entries"
    end
    resources :progress_jobs, only: %i[index] do  # long-running task progress (live via SSE)
      post :run, on: :collection
      post :cancel, on: :member
    end
    resources :scheduled_jobs, only: %i[index new create edit update destroy] do  # recurring jobs
      post :run_now, on: :member
    end
    resources :field_definitions, only: %i[index new create destroy]
    resources :notifications, only: %i[index] do
      post :mark_read, on: :member
    end
    resources :webhook_endpoints, only: %i[index new create destroy]
    resources :api_tokens, only: %i[index create destroy]
    resources :comments, only: %i[create]
    # Settings are keyed by a dotted string ("rental.late_fee_per_day"), which a
    # resourceful :id would truncate at the dot, so the key travels as a param.
    get    "configs",      to: "configs#index",  as: :configs
    get    "configs/edit", to: "configs#edit",   as: :edit_config
    patch  "configs",      to: "configs#update"
    delete "configs",      to: "configs#reset"
    # Feature flags are keyed by a dotted name too, so the name travels as a param.
    get    "features",         to: "features#index",   as: :features
    post   "features/enable",  to: "features#enable",  as: :enable_feature
    post   "features/disable", to: "features#disable", as: :disable_feature
    delete "features",         to: "features#reset"
    # A capability gated by a flag (Loam::Features.require_feature!) — a demo of
    # the guard: off for Krakow (404), on for Warsaw once enabled in seeds.
    get "dashboard/beta", to: "dashboard#beta", as: :beta_dashboard
    get   "dashboard_widgets", to: "dashboard_widgets#index", as: :dashboard_widgets  # dashboard settings
    patch "dashboard_widgets", to: "dashboard_widgets#update"
    get "search", to: "search#index"
  end

  namespace :api do
    resources :customers, defaults: { format: :json }
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
