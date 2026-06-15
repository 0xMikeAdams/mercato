defmodule Mercato.Checkout.PaymentProvider do
  @moduledoc """
  Behaviour for creating machine-consumable payment sessions or intents.

  Advanced/internal: this is the orchestration seam for *programmatic checkout*. Most
  integrations should NOT implement this — implement `Mercato.Behaviours.PaymentGateway`
  and configure `:payment_gateway` (see `Mercato`). The default provider
  (`Mercato.Checkout.Providers.DefaultPaymentProvider`) bridges to it. Override
  `:payment_provider` only for a fully custom payment flow (e.g. redirect/client-secret).
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
