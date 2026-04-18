defmodule Mercato.Checkout.PricingProvider do
  @moduledoc """
  Behaviour for deterministic programmatic pricing.
  """

  alias Mercato.Cart.Cart
  alias Mercato.Checkout.ProgrammaticCheckoutRequest

  @callback price_cart(Cart.t(), ProgrammaticCheckoutRequest.t(), keyword()) ::
              {:ok,
               %{
                 subtotal: Decimal.t(),
                 discount_total: Decimal.t(),
                 shipping_total: Decimal.t(),
                 tax_total: Decimal.t(),
                 duties_total: Decimal.t(),
                 grand_total: Decimal.t()
               }}
              | {:error, term()}
end
