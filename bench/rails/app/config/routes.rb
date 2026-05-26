Rails.application.routes.draw do
  get "embed",  to: "embed#show"
  get "health", to: "health#show"
end
