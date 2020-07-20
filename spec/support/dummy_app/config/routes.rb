Rails.application.routes.draw do
  resources :posts

  get "/trigger-pg-server-error" => "posts#trigger_pg_server_error"
end
