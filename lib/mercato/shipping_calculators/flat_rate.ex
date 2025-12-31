defmodule Mercato.ShippingCalculators.FlatRate do
  @moduledoc """
  Flat rate shipping calculator implementation.

  This implementation provides simple flat-rate shipping calculation with
  configurable rates and free shipping thresholds. It supports different
  rates based on shipping method and can be configured per application.

  ## Configuration

      config :mercato, :shipping_calculator, Mercato.ShippingCalculators.FlatRate

      config :mercato, Mercato.ShippingCalculators.FlatRate,
        default_rate: Decimal.new("9.99"),
        free_shipping_threshold: Decimal.new("75.00"),
        methods: [
          %{
            id: "standard",
            name: "Standard Shipping",
            description: "5-7 business days",
            rate: Decimal.new("9.99"),
            estimated_days: 7
          },
          %{
            id: "expedited",
            name: "Expedited Shipping",
            description: "2-3 business days",
            rate: Decimal.new("19.99"),
            estimated_days: 3
          }
        ]

  ## Behavior

  - Returns configured flat rate for each shipping method
  - Supports free shipping when cart total exceeds threshold
  - All destinations receive the same rates (no geographic restrictions)
  """

  @behaviour Mercato.Behaviours.ShippingCalculator

  alias Mercato.Cart.Cart
  alias Mercato.Customers.Address

  @impl true
  def calculate_shipping(%Cart{} = cart, %Address{} = _destination, opts) do
    method_id = Keyword.get(opts, :method, "standard")

    case get_method_by_id(method_id) do
      nil ->
        {:error, :invalid_shipping_method}

      method ->
        rate = method.rate

        if qualifies_for_free_shipping?(cart) do
          {:ok, Decimal.new("0.00")}
        else
          {:ok, rate}
        end
    end
  end

  @impl true
  def get_available_methods(%Address{} = _destination) do
    config()
    |> Keyword.get(:methods, default_methods())
    |> Enum.map(fn method ->
      %{
        id: method.id,
        name: method.name,
        description: method.description,
        estimated_days: method.estimated_days
      }
    end)
  end

  # Private helper functions

  defp get_method_by_id(method_id) do
    config()
    |> Keyword.get(:methods, default_methods())
    |> Enum.find(&(&1.id == method_id))
  end

  defp qualifies_for_free_shipping?(%Cart{subtotal: subtotal}) do
    threshold = config() |> Keyword.get(:free_shipping_threshold, Decimal.new("75.00"))
    Decimal.compare(subtotal, threshold) != :lt
  end

  defp config do
    Application.get_env(:mercato, __MODULE__, [])
  end

  defp default_methods do
    [
      %{
        id: "standard",
        name: "Standard Shipping",
        description: "5-7 business days",
        rate: Decimal.new("9.99"),
        estimated_days: 7
      },
      %{
        id: "expedited",
        name: "Expedited Shipping",
        description: "2-3 business days",
        rate: Decimal.new("19.99"),
        estimated_days: 3
      }
    ]
  end
end
