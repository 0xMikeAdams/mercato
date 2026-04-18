defmodule Mercato.Checkout.CheckoutProvider do
  @moduledoc """
  Behaviour for creating redirect or managed checkout sessions from a priced cart.
  """

  alias Mercato.Checkout.{
    CheckoutSession,
    ProgrammaticCheckoutRequest,
    ProgrammaticCheckoutResponse
  }

  @callback create_checkout_session(
              ProgrammaticCheckoutRequest.t(),
              ProgrammaticCheckoutResponse.t(),
              keyword()
            ) :: {:ok, CheckoutSession.t()} | {:error, term()}
end
