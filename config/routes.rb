# frozen_string_literal: true

RecordingStudioStripe::Engine.routes.draw do
  root to: "billing#show"
  get "plans", to: "plans#index", as: :engine_plans
  post "checkout", to: "checkouts#create"
  patch "subscription", to: "subscriptions#update"
  post "subscription/cancel", to: "subscriptions#destroy"
  post "subscription/resume", to: "subscriptions#resume"
  post "allowances", to: "allowances#create"

  namespace :admin do
    resources :products, only: %i[new create edit update]
    resources :prices, only: %i[new create]
    resources :meters, only: %i[new create]
    resources :paywalls, only: %i[new create]
  end
end
