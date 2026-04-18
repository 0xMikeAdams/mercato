defmodule Mercato.Checkout.Providers.DefaultPricingProvider do
  @moduledoc """
  Default deterministic pricing provider backed by Mercato's existing cart calculator.
  """

  @behaviour Mercato.Checkout.PricingProvider

  alias Decimal, as: D
  alias Mercato.Cart.Calculator
  alias Mercato.Checkout.Address

  @impl true
  def price_cart(cart, request, opts) do
    pricing_opts =
      []
      |> put_opt(:destination, Address.to_customer_address(request.shipping_address))
      |> put_opt(:method, request.shipping_method)
      |> put_opt(:shipping_calculator, Keyword.get(opts, :shipping_calculator))
      |> put_opt(:tax_calculator, Keyword.get(opts, :tax_calculator))
      |> put_opt(:duties_total, D.new("0.00"))

    {:ok, Calculator.recalculate_totals(cart, pricing_opts)}
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
