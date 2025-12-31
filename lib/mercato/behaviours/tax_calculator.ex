defmodule Mercato.Behaviours.TaxCalculator do
  @moduledoc """
  Behaviour for implementing tax calculation.

  This behaviour defines the standard interface for calculating taxes on cart
  contents based on destination address, product types, and applicable tax rules.
  Implementations can integrate with tax services, use flat rates, or implement
  custom tax logic based on jurisdiction requirements.

  ## Example Implementation

      defmodule MyApp.TaxCalculators.Avalara do
        @behaviour Mercato.Behaviours.TaxCalculator

        @impl true
        def calculate_tax(cart, destination, opts) do
          # Avalara API integration logic
          total_tax = calculate_sales_tax(cart.subtotal, destination)
          {:ok, total_tax}
        end

        defp calculate_sales_tax(amount, %{state: "CA"}) do
          Decimal.mult(amount, Decimal.new("0.0875"))  # 8.75% CA sales tax
        end

        defp calculate_sales_tax(amount, %{state: "NY"}) do
          Decimal.mult(amount, Decimal.new("0.08"))     # 8% NY sales tax
        end

        defp calculate_sales_tax(_amount, _destination) do
          Decimal.new("0")  # No tax for other states
        end
      end

  ## Configuration

  Configure your tax calculator in your application config:

      config :mercato, :tax_calculator, MyApp.TaxCalculators.Avalara
  """

  alias Mercato.Cart.Cart
  alias Mercato.Customers.Address

  @doc """
  Calculates tax amount for a cart based on destination.

  This function should calculate the total tax amount based on the cart contents
  and destination address. The calculation should consider factors such as:

  - Destination tax jurisdiction (country, state, city)
  - Product tax categories and exemptions
  - Customer tax exemption status
  - Business vs. consumer sales
  - Digital vs. physical products

  ## Parameters

    * `cart` - The cart struct containing items and totals
    * `destination` - The destination address struct for tax jurisdiction
    * `opts` - Additional options such as:
      * `:customer_type` - "business" or "consumer"
      * `:tax_exempt` - Whether customer is tax exempt
      * `:exemption_certificate` - Tax exemption certificate number
      * `:currency` - Currency for calculation

  ## Returns

    * `{:ok, amount}` - Total tax amount as a Decimal
    * `{:error, reason}` - Calculation failed with error reason

  The tax amount should be the total tax to be added to the cart, not the
  tax rate. For example, if the cart subtotal is $100 and the tax rate is
  8.5%, this function should return `{:ok, Decimal.new("8.50")}`.

  ## Examples

      iex> cart = %Cart{subtotal: Decimal.new("100.00")}
      iex> address = %Address{country: "US", state: "CA", city: "Los Angeles"}
      iex> calculate_tax(cart, address, customer_type: "consumer")
      {:ok, Decimal.new("9.50")}

      iex> calculate_tax(cart, address, tax_exempt: true)
      {:ok, Decimal.new("0.00")}

      iex> calculate_tax(cart, %Address{country: "INVALID"}, [])
      {:error, :invalid_tax_jurisdiction}
  """
  @callback calculate_tax(
              cart :: Cart.t(),
              destination :: Address.t(),
              opts :: keyword()
            ) :: {:ok, amount :: Decimal.t()} | {:error, reason :: term()}
end
