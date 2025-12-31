# Sample Router Integration
# Add this to your existing router or create a new scope

defmodule YourAppWeb.Router do
  use YourAppWeb, :router
  import Mercato.Router

  # ... your existing routes

  scope "/api", YourAppWeb do
    pipe_through :api

    # Mount Mercato API routes
    mercato_api_routes()
  end

  # Referral shortlinks
  scope "/", YourAppWeb do
    pipe_through :browser

    get "/r/:code", Mercato.ReferralController, :redirect
  end
end
