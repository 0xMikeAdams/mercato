defmodule Mercato.TestEndpoint do
  use Phoenix.Endpoint, otp_app: :mercato

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(Mercato.TestRouter)
end
