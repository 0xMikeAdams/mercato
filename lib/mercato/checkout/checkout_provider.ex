defmodule Mercato.Checkout.CheckoutProvider do
  @moduledoc """
  Behaviour for creating redirect or managed checkout sessions from a priced cart.

  Advanced/internal orchestration seam for *programmatic checkout*. It composes the
  payment/shipping/pricing layers; it is not a payment/shipping/tax integration point.
  Implement `Mercato.Behaviours.{PaymentGateway,ShippingCalculator,TaxCalculator}` for
  those (see `Mercato`). Override `:checkout_provider` only to replace the whole flow.
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
