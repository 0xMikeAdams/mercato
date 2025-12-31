defmodule Mercato.Behaviours.ShippingCalculator do
  @moduledoc """
  Behaviour for implementing shipping cost calculation.

  This behaviour defines the standard interface for calculating shipping costs
  and retrieving available shipping methods based on cart contents and destination.
  Implementations can integrate with shipping providers, use flat rates, or
  implement custom shipping logic.

  ## Example Implementation

      defmodule MyApp.ShippingCalculators.UPS do
        @behaviour Mercato.Behaviours.ShippingCalculator

        @impl true
        def calculate_shipping(cart, destination, opts) do
          # UPS API integration logic
          {:ok, Decimal.new("12.50")}
        end

        @impl true
        def get_available_methods(destination) do
          [
            %{
              id: "ups_ground",
              name: "UPS Ground",
              description: "5-7 business days",
              estimated_days: 7
            },
            %{
              id: "ups_next_day",
              name: "UPS Next Day Air",
              description: "Next business day",
              estimated_days: 1
            }
          ]
        end
      end

  ## Configuration

  Configure your shipping calculator in your application config:

      config :mercato, :shipping_calculator, MyApp.ShippingCalculators.UPS
  """

  alias Mercato.Cart.Cart
  alias Mercato.Customers.Address

  @doc """
  Calculates shipping cost for a cart to a destination.

  This function should calculate the shipping cost based on the cart contents
  (items, weights, dimensions) and the destination address. The calculation
  can consider factors such as:

  - Total cart weight and dimensions
  - Shipping distance or zones
  - Selected shipping method
  - Cart value for free shipping thresholds
  - Item-specific shipping rules

  ## Parameters

    * `cart` - The cart struct containing items and totals
    * `destination` - The shipping address struct
    * `opts` - Additional options such as:
      * `:method` - Specific shipping method ID
      * `:currency` - Currency for calculation
      * `:expedited` - Whether to use expedited shipping
      * `:insurance` - Whether to include shipping insurance

  ## Returns

    * `{:ok, amount}` - Shipping cost as a Decimal
    * `{:error, reason}` - Calculation failed with error reason

  ## Examples

      iex> cart = %Cart{subtotal: Decimal.new("50.00")}
      iex> address = %Address{country: "US", state: "CA", postal_code: "90210"}
      iex> calculate_shipping(cart, address, method: "standard")
      {:ok, Decimal.new("8.99")}

      iex> calculate_shipping(cart, address, method: "invalid")
      {:error, :invalid_shipping_method}
  """
  @callback calculate_shipping(
              cart :: Cart.t(),
              destination :: Address.t(),
              opts :: keyword()
            ) :: {:ok, amount :: Decimal.t()} | {:error, reason :: term()}

  @doc """
  Returns available shipping methods for a destination.

  This function should return a list of shipping methods available for the
  given destination. Each method should include sufficient information for
  the customer to make an informed choice.

  ## Parameters

    * `destination` - The shipping address struct

  ## Returns

  A list of maps, each representing a shipping method with the following keys:
    * `:id` - Unique method identifier (required)
    * `:name` - Human-readable method name (required)
    * `:description` - Method description (optional)
    * `:estimated_days` - Estimated delivery days (optional)
    * `:carrier` - Shipping carrier name (optional)
    * `:service_code` - Carrier service code (optional)

  ## Examples

      iex> address = %Address{country: "US", state: "CA"}
      iex> get_available_methods(address)
      [
        %{
          id: "standard",
          name: "Standard Shipping",
          description: "5-7 business days",
          estimated_days: 7
        },
        %{
          id: "expedited",
          name: "Expedited Shipping",
          description: "2-3 business days",
          estimated_days: 3
        }
      ]
  """
  @callback get_available_methods(destination :: Address.t()) :: [map()]
end
