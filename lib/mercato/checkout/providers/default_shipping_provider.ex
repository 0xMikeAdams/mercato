defmodule Mercato.Checkout.Providers.DefaultShippingProvider do
  @moduledoc """
  Adapter that exposes Mercato's configured shipping calculator through the
  programmatic checkout shipping-provider behaviour.
  """

  @behaviour Mercato.Checkout.ShippingProvider

  alias Decimal, as: D
  alias Mercato.Cart
  alias Mercato.Checkout.Address

  @impl true
  def calculate_shipping(cart, %Address{} = address, opts) do
    Cart.calculate_shipping_cost(cart.id, Address.to_customer_address(address), opts)
  rescue
    _error -> {:ok, D.new("0.00")}
  end

  @impl true
  def list_shipping_methods(%Address{} = address, opts) do
    methods =
      Cart.get_shipping_methods(
        Address.to_customer_address(address),
        Keyword.take(opts, [:shipping_calculator])
      )

    {:ok, methods}
  end
end
