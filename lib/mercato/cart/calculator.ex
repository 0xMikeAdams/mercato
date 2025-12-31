defmodule Mercato.Cart.Calculator do
  @moduledoc """
  Calculator module for cart totals.

  This module provides functions for calculating cart subtotals, discounts,
  shipping, taxes, and grand totals. It integrates with pluggable behaviours
  for shipping and tax calculations.

  ## Features

  - Subtotal calculation from cart items
  - Discount calculation from applied coupons
  - Shipping cost calculation via ShippingCalculator behaviour
  - Tax calculation via TaxCalculator behaviour
  - Grand total calculation

  ## Usage

      # Calculate all totals for a cart
      totals = Mercato.Cart.Calculator.calculate_totals(cart, opts)

      # Calculate subtotal only
      subtotal = Mercato.Cart.Calculator.calculate_subtotal(cart)

      # Calculate discount
      discount = Mercato.Cart.Calculator.calculate_discount(cart, coupon)
  """

  alias Mercato.Cart.Cart
  alias Decimal

  @doc """
  Calculates the subtotal for a cart.

  The subtotal is the sum of all cart item total prices before any discounts,
  shipping, or taxes are applied.

  ## Examples

      iex> calculate_subtotal(cart)
      #Decimal<29.99>
  """
  def calculate_subtotal(%Cart{items: items}) do
    items
    |> Enum.map(& &1.total_price)
    |> Enum.reduce(Decimal.new("0.00"), &Decimal.add/2)
  end

  @doc """
  Calculates the discount total for a cart.

  If the cart has an applied coupon, calculates the discount amount.
  Otherwise, returns zero.

  ## Examples

      iex> calculate_discount(cart)
      #Decimal<5.00>
  """
  def calculate_discount(%Cart{applied_coupon_id: nil}) do
    Decimal.new("0.00")
  end

  def calculate_discount(%Cart{applied_coupon_id: coupon_id} = cart) when not is_nil(coupon_id) do
    alias Mercato.Coupons

    try do
      coupon = Coupons.get_coupon!(coupon_id)
      {:ok, discount_amount} = Coupons.apply_coupon(coupon, cart)
      discount_amount
    rescue
      Ecto.NoResultsError ->
        # Coupon no longer exists, return zero discount
        Decimal.new("0.00")
    end
  end

  def calculate_discount(%Cart{}) do
    Decimal.new("0.00")
  end

  @doc """
  Calculates the shipping total for a cart.

  This function integrates with the configured ShippingCalculator behaviour.
  If no shipping calculator is configured or no destination is provided,
  it returns zero.

  ## Options

  - `:destination` - The shipping address (required for calculation)
  - `:shipping_calculator` - Override the configured shipping calculator

  ## Examples

      iex> calculate_shipping(cart, destination: address)
      #Decimal<10.00>

      iex> calculate_shipping(cart)
      #Decimal<0.00>
  """
  def calculate_shipping(cart, opts \\ []) do
    destination = Keyword.get(opts, :destination)
    calculator = Keyword.get(opts, :shipping_calculator) || get_shipping_calculator()

    if destination && calculator do
      case calculator.calculate_shipping(cart, destination, opts) do
        {:ok, amount} -> amount
        {:error, _reason} -> Decimal.new("0.00")
      end
    else
      cart.shipping_total || Decimal.new("0.00")
    end
  end

  @doc """
  Calculates the tax total for a cart.

  This function integrates with the configured TaxCalculator behaviour.
  If no tax calculator is configured or no destination is provided,
  it returns zero.

  ## Options

  - `:destination` - The tax address (required for calculation)
  - `:tax_calculator` - Override the configured tax calculator

  ## Examples

      iex> calculate_tax(cart, destination: address)
      #Decimal<2.50>

      iex> calculate_tax(cart)
      #Decimal<0.00>
  """
  def calculate_tax(cart, opts \\ []) do
    destination = Keyword.get(opts, :destination)
    calculator = Keyword.get(opts, :tax_calculator) || get_tax_calculator()

    if destination && calculator do
      case calculator.calculate_tax(cart, destination, opts) do
        {:ok, amount} -> amount
        {:error, _reason} -> Decimal.new("0.00")
      end
    else
      cart.tax_total || Decimal.new("0.00")
    end
  end

  @doc """
  Calculates the grand total for a cart.

  The grand total is calculated as:
  subtotal - discount_total + shipping_total + tax_total

  ## Examples

      iex> calculate_grand_total(cart)
      #Decimal<37.49>
  """
  def calculate_grand_total(%Cart{} = cart) do
    cart.subtotal
    |> Decimal.sub(cart.discount_total || Decimal.new("0.00"))
    |> Decimal.add(cart.shipping_total || Decimal.new("0.00"))
    |> Decimal.add(cart.tax_total || Decimal.new("0.00"))
  end

  @doc """
  Calculates all totals for a cart and returns a map.

  This is a convenience function that calculates subtotal, discount, shipping,
  tax, and grand total in one call.

  ## Options

  - `:destination` - The shipping/tax address
  - `:shipping_calculator` - Override the configured shipping calculator
  - `:tax_calculator` - Override the configured tax calculator

  ## Examples

      iex> calculate_totals(cart, destination: address)
      %{
        subtotal: #Decimal<29.99>,
        discount_total: #Decimal<5.00>,
        shipping_total: #Decimal<10.00>,
        tax_total: #Decimal<2.50>,
        grand_total: #Decimal<37.49>
      }
  """
  def calculate_totals(%Cart{} = cart, opts \\ []) do
    subtotal = calculate_subtotal(cart)
    discount_total = calculate_discount(cart)
    shipping_total = calculate_shipping(cart, opts)
    tax_total = calculate_tax(cart, opts)

    # Create a temporary cart with calculated values for grand total calculation
    temp_cart = %{
      cart
      | subtotal: subtotal,
        discount_total: discount_total,
        shipping_total: shipping_total,
        tax_total: tax_total
    }

    grand_total = calculate_grand_total(temp_cart)

    %{
      subtotal: subtotal,
      discount_total: discount_total,
      shipping_total: shipping_total,
      tax_total: tax_total,
      grand_total: grand_total
    }
  end

  @doc """
  Recalculates and updates all totals for a cart.

  This function calculates all totals and returns a map suitable for
  updating the cart via Cart.totals_changeset/2.

  ## Options

  Same as `calculate_totals/2`

  ## Examples

      iex> recalculate_totals(cart, destination: address)
      %{
        subtotal: #Decimal<29.99>,
        discount_total: #Decimal<5.00>,
        shipping_total: #Decimal<10.00>,
        tax_total: #Decimal<2.50>,
        grand_total: #Decimal<37.49>
      }
  """
  def recalculate_totals(cart, opts \\ []) do
    calculate_totals(cart, opts)
  end

  # Private Functions

  defp get_shipping_calculator do
    Application.get_env(:mercato, :shipping_calculator)
  end

  defp get_tax_calculator do
    Application.get_env(:mercato, :tax_calculator)
  end
end
