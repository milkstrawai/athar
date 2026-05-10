# frozen_string_literal: true

Athar::Engine.routes.draw do
  root "dashboard#index"
  resources :deletions,    only: [:show]
  resources :table_events, only: [:show]
  resource :theme, only: [:update]
end
