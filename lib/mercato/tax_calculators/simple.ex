defmodule Mercato.TaxCalculators.Simple do
  @moduledoc """
  Simple tax calculator implementation.

  This implementation provides basic tax calculation with configurable rates
  based on destination state/province. It supports tax exemptions and different
  rates for different jurisdictions.

  ## Configuration

      config :mercato, :tax_calculator, Mercato.TaxCalculators.Simple

      config :mercato, Mercato.TaxCalculators.Simple,
        default_rate: Decimal.new("0.08"),  # 8% default rate
        rates: %{
          "CA" => Decimal.new("0.0875"),     # 8.75% California
          "NY" => Decimal.new("0.08"),       # 8% New York
          "TX" => Decimal.new("0.0625"),     # 6.25% Texas
          "FL" => Decimal.new("0.06"),       # 6% Florida
          "WA" => Decimal.new("0.065")       # 6.5% Washington
        },
        tax_exempt_states: ["OR", "NH", "DE", "MT"]  # No sales tax states

  ## Behavior

  - Calculates tax based on cart subtotal and destination state
  - Supports tax exemption for configured states
  - Honors customer tax exemption status
  - Returns zero tax for tax-exempt customers or states
  """

  @behaviour Mercato.Behaviours.TaxCalculator

  alias Mercato.Cart.Cart
  alias Mercato.Customers.Address

  @impl true
  def calculate_tax(%Cart{} = cart, %Address{} = destination, opts) do
    cond do
      Keyword.get(opts, :tax_exempt, false) ->
        {:ok, Decimal.new("0.00")}

      tax_exempt_state?(destination.state) ->
        {:ok, Decimal.new("0.00")}

      true ->
        rate = get_tax_rate(destination.state)
        tax_amount = Decimal.mult(cart.subtotal, rate)
        {:ok, tax_amount}
    end
  end

  # Private helper functions

  defp get_tax_rate(state) when is_binary(state) do
    rates = config() |> Keyword.get(:rates, %{})
    default_rate = config() |> Keyword.get(:default_rate, Decimal.new("0.08"))

    Map.get(rates, String.upcase(state), default_rate)
  end

  defp get_tax_rate(_), do: Decimal.new("0.00")

  defp tax_exempt_state?(state) when is_binary(state) do
    exempt_states = config() |> Keyword.get(:tax_exempt_states, [])
    String.upcase(state) in exempt_states
  end

  defp tax_exempt_state?(_), do: false

  defp config do
    Application.get_env(:mercato, __MODULE__, [])
  end
end
