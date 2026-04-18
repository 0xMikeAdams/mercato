defmodule Mercato.Checkout.PaymentProvider do
  @moduledoc """
  Behaviour for creating machine-consumable payment sessions or intents.
  """

  alias Mercato.Checkout.{
    CheckoutSession,
    ProgrammaticCheckoutRequest,
    ProgrammaticCheckoutResponse
  }

  @callback create_payment_session(
              ProgrammaticCheckoutRequest.t(),
              ProgrammaticCheckoutResponse.t(),
              keyword()
            ) :: {:ok, CheckoutSession.t()} | {:error, term()}
end
