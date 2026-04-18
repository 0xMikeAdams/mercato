defmodule Mercato.Checkout.ShippingProvider do
  @moduledoc """
  Behaviour for shipping calculations used by programmatic checkout.
  """

  alias Mercato.Cart.Cart
  alias Mercato.Checkout.Address

  @callback calculate_shipping(Cart.t(), Address.t(), keyword()) ::
              {:ok, Decimal.t()} | {:error, term()}

  @callback list_shipping_methods(Address.t(), keyword()) ::
              {:ok, [map()]} | {:error, term()}
end
