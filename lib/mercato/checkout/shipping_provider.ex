defmodule Mercato.Checkout.ShippingProvider do
  @moduledoc """
  Behaviour for shipping calculations used by programmatic checkout.

  Advanced/internal orchestration seam. Most integrations should implement
  `Mercato.Behaviours.ShippingCalculator` and configure `:shipping_calculator`
  (see `Mercato`); the default provider delegates to it. Override `:shipping_provider`
  only to fully replace programmatic-checkout shipping.
  """

  alias Mercato.Cart.Cart
  alias Mercato.Checkout.Address

  @callback calculate_shipping(Cart.t(), Address.t(), keyword()) ::
              {:ok, Decimal.t()} | {:error, term()}

  @callback list_shipping_methods(Address.t(), keyword()) ::
              {:ok, [map()]} | {:error, term()}
end
