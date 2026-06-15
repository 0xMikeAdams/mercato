defmodule Mercato.Checkout.PricingProvider do
  @moduledoc """
  Behaviour for deterministic programmatic pricing.

  Advanced/internal orchestration seam. Most integrations should implement
  `Mercato.Behaviours.ShippingCalculator` / `Mercato.Behaviours.TaxCalculator` and
  configure `:shipping_calculator` / `:tax_calculator` (see `Mercato`); the default
  provider delegates to them. Override `:pricing_provider` only to fully replace pricing.
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
