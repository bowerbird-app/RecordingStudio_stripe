# frozen_string_literal: true

RecordingStudioStripe::Engine.routes.draw do
  root to: "billing#show"
  get "plans", to: "plans#index", as: :engine_plans
  post "checkout", to: "checkouts#create"
  post "portal", to: "portals#create"
  get "subscription/change", to: "subscriptions#edit", as: :subscription_change
  patch "subscription", to: "subscriptions#update"
  get "subscription/cancel", to: "subscriptions#confirm_cancel", as: :subscription_cancel_confirm
  post "subscription/cancel", to: "subscriptions#destroy"
  post "subscription/resume", to: "subscriptions#resume"
  post "subscription/keep", to: "subscriptions#keep"
  post "allowances", to: "allowances#create"

  namespace :admin do
    resources :products, only: %i[new create edit update]
    resources :prices, only: %i[new create edit update]
    resources :meters, only: %i[new create]
    resources :paywalls, only: %i[new create]
  end
end
