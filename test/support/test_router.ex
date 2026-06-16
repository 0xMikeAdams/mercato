defmodule Mercato.TestRouter do
  use Phoenix.Router

  import Mercato.Router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", alias: Mercato, as: false do
    pipe_through(:api)
    mercato_public_routes()
    mercato_customer_routes()
    mercato_admin_routes()
  end

  mercato_referral_routes(api_prefix: "/api")
end
