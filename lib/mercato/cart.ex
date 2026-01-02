defmodule Mercato.Cart do
  @moduledoc """
  The Cart context.

  This module provides the public API for managing shopping carts, including
  creating carts, adding/removing items, and calculating totals.

  ## Features

  - Anonymous and authenticated cart sessions
  - In-memory cart state with GenServer management
  - Automatic total calculations
  - Real-time event broadcasting
  - Cart expiration and cleanup

  ## Usage

      # Create a new cart
      {:ok, cart} = Mercato.Cart.create_cart(%{cart_token: "unique-token"})

      # Add an item to the cart
      {:ok, cart} = Mercato.Cart.add_item(cart.id, product_id, 2)

      # Update item quantity
      {:ok, cart} = Mercato.Cart.update_item_quantity(cart.id, item_id, 5)

      # Remove an item
      {:ok, cart} = Mercato.Cart.remove_item(cart.id, item_id)

      # Clear the cart
      {:ok, cart} = Mercato.Cart.clear_cart(cart.id)

      # Get cart by ID
      {:ok, cart} = Mercato.Cart.get_cart(cart.id)
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mercato
  alias Mercato.Cart.{Cart, CartItem, Calculator, Manager}
  alias Mercato.Catalog
  alias Mercato.Events

  @doc """
  Gets a cart by ID.

  Returns the cart with preloaded items and product associations.

  ## Examples

      iex> get_cart(cart_id)
      {:ok, %Cart{}}

      iex> get_cart("non-existent")
      {:error, :not_found}
  """
  def get_cart(cart_id) do
    case repo().get(Cart, cart_id) do
      nil ->
        {:error, :not_found}

      cart ->
        cart = repo().preload(cart, items: [:product, :variant])
        {:ok, cart}
    end
  end

  @doc """
  Gets a cart by cart token.

  ## Examples

      iex> get_cart_by_token("token123")
      {:ok, %Cart{}}

      iex> get_cart_by_token("non-existent")
      {:error, :not_found}
  """
  def get_cart_by_token(cart_token) do
    case repo().get_by(Cart, cart_token: cart_token) do
      nil ->
        {:error, :not_found}

      cart ->
        cart = repo().preload(cart, items: [:product, :variant])
        {:ok, cart}
    end
  end

  @doc """
  Gets a cart by user ID.

  Returns the most recent active cart for the user.

  ## Examples

      iex> get_cart_by_user(user_id)
      {:ok, %Cart{}}

      iex> get_cart_by_user("non-existent")
      {:error, :not_found}
  """
  def get_cart_by_user(user_id) do
    query =
      from c in Cart,
        where: c.user_id == ^user_id and c.status == "active",
        order_by: [desc: c.updated_at],
        limit: 1

    case repo().one(query) do
      nil ->
        {:error, :not_found}

      cart ->
        cart = repo().preload(cart, items: [:product, :variant])
        {:ok, cart}
    end
  end

  @doc """
  Creates a new cart.

  ## Examples

      iex> create_cart(%{cart_token: "token123"})
      {:ok, %Cart{}}

      iex> create_cart(%{user_id: user_id})
      {:ok, %Cart{}}

      iex> create_cart(%{})
      {:error, %Ecto.Changeset{}}
  """
  def create_cart(attrs \\ %{}) do
    %Cart{}
    |> Cart.create_changeset(attrs)
    |> repo().insert()
    |> case do
      {:ok, cart} ->
        # Start a cart manager GenServer for this cart (skip in test environment)
        unless Application.get_env(:mercato, :env) == :test do
          case Manager.Supervisor.start_cart(cart.id) do
            {:ok, _pid} ->
              Logger.debug("Started cart manager for cart #{cart.id}")

            {:error, reason} ->
              Logger.warning("Failed to start cart manager for cart #{cart.id}: #{inspect(reason)}")
          end
        end

        {:ok, repo().preload(cart, :items)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Adds an item to a cart.

  If the product (or variant) already exists in the cart, the quantity is increased.
  Otherwise, a new cart item is created.

  ## Options

  - `:variant_id` - The product variant ID (optional)

  ## Examples

      iex> add_item(cart_id, product_id, 2)
      {:ok, %Cart{}}

      iex> add_item(cart_id, product_id, 2, variant_id: variant_id)
      {:ok, %Cart{}}

      iex> add_item("non-existent", product_id, 2)
      {:error, :not_found}
  """
  def add_item(cart_id, product_id, quantity, opts \\ []) when quantity > 0 do
    variant_id = Keyword.get(opts, :variant_id)

    with {:ok, cart} <- get_cart(cart_id),
         {:ok, product} <- fetch_product(product_id),
         {:ok, price} <- get_item_price(product, variant_id) do
      # Check if item already exists in cart
      existing_item = find_cart_item(cart, product_id, variant_id)

      result =
        if existing_item do
          # Update existing item quantity
          new_quantity = existing_item.quantity + quantity

          existing_item
          |> CartItem.changeset(%{quantity: new_quantity})
          |> repo().update()
        else
          # Create new cart item
          %CartItem{}
          |> CartItem.changeset(%{
            cart_id: cart_id,
            product_id: product_id,
            variant_id: variant_id,
            quantity: quantity,
            unit_price: price
          })
          |> repo().insert()
        end

      case result do
        {:ok, _item} ->
          # Recalculate totals and broadcast event
          cart = recalculate_and_broadcast(cart_id)
          {:ok, cart}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Updates the quantity of a cart item.

  ## Examples

      iex> update_item_quantity(cart_id, item_id, 5)
      {:ok, %Cart{}}

      iex> update_item_quantity(cart_id, "non-existent", 5)
      {:error, :not_found}
  """
  def update_item_quantity(cart_id, item_id, quantity) when quantity > 0 do
    with {:ok, cart} <- get_cart(cart_id),
         {:ok, item} <- get_cart_item(cart, item_id) do
      item
      |> CartItem.changeset(%{quantity: quantity})
      |> repo().update()
      |> case do
        {:ok, _item} ->
          cart = recalculate_and_broadcast(cart_id)
          {:ok, cart}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Removes an item from a cart.

  ## Examples

      iex> remove_item(cart_id, item_id)
      {:ok, %Cart{}}

      iex> remove_item(cart_id, "non-existent")
      {:error, :not_found}
  """
  def remove_item(cart_id, item_id) do
    with {:ok, cart} <- get_cart(cart_id),
      {:ok, item} <- get_cart_item(cart, item_id) do
      repo().delete(item)

      cart = recalculate_and_broadcast(cart_id)
      Events.broadcast_cart_item_removed(cart, item_id)

      {:ok, cart}
    end
  end

  @doc """
  Clears all items from a cart.

  ## Examples

      iex> clear_cart(cart_id)
      {:ok, %Cart{}}

      iex> clear_cart("non-existent")
      {:error, :not_found}
  """
  def clear_cart(cart_id) do
    with {:ok, cart} <- get_cart(cart_id) do
      # Delete all cart items
      from(i in CartItem, where: i.cart_id == ^cart_id)
      |> repo().delete_all()

      # Reset totals
      cart
      |> Cart.totals_changeset(%{
        subtotal: Decimal.new("0.00"),
        discount_total: Decimal.new("0.00"),
        shipping_total: Decimal.new("0.00"),
        tax_total: Decimal.new("0.00"),
        grand_total: Decimal.new("0.00")
      })
      |> repo().update()
      |> case do
        {:ok, updated_cart} ->
          updated_cart = repo().preload(updated_cart, :items, force: true)
          Events.broadcast_cart_cleared(cart_id)
          {:ok, updated_cart}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Applies a coupon to a cart.

  Validates the coupon against the cart and applies it if valid.
  This will recalculate cart totals to include the discount.

  ## Examples

      iex> apply_coupon(cart_id, "SAVE10")
      {:ok, %Cart{}}

      iex> apply_coupon(cart_id, "INVALID")
      {:error, :invalid_coupon}

      iex> apply_coupon(cart_id, "EXPIRED")
      {:error, :expired}
  """
  def apply_coupon(cart_id, coupon_code) do
    alias Mercato.Coupons

    with {:ok, cart} <- get_cart(cart_id),
         {:ok, coupon} <- Coupons.validate_coupon(coupon_code, cart) do
      # Apply coupon to cart
      cart
      |> Cart.coupon_changeset(%{applied_coupon_id: coupon.id})
      |> repo().update()
      |> case do
        {:ok, _updated_cart} ->
          # Recalculate totals with coupon applied
          cart = recalculate_and_broadcast(cart_id)
          {:ok, cart}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Removes a coupon from a cart.

  ## Examples

      iex> remove_coupon(cart_id)
      {:ok, %Cart{}}
  """
  def remove_coupon(cart_id) do
    with {:ok, cart} <- get_cart(cart_id) do
      cart
      |> Cart.coupon_changeset(%{applied_coupon_id: nil})
      |> repo().update()
      |> case do
        {:ok, _updated_cart} ->
          # Recalculate totals without coupon
          cart = recalculate_and_broadcast(cart_id)
          {:ok, cart}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Applies a referral code to a cart.

  Associates the cart with a referral code for commission tracking.
  The referral code will be transferred to the order when the cart is converted.

  ## Examples

      iex> apply_referral_code(cart_id, "ABC123")
      {:ok, %Cart{}}

      iex> apply_referral_code(cart_id, "INVALID")
      {:error, :referral_code_not_found}
  """
  def apply_referral_code(cart_id, referral_code) do
    alias Mercato.Referrals

    with {:ok, cart} <- get_cart(cart_id),
         {:ok, referral_code_record} <- Referrals.get_referral_code(referral_code) do
      # Apply referral code to cart
      cart
      |> Cart.referral_changeset(%{referral_code_id: referral_code_record.id})
      |> repo().update()
      |> case do
        {:ok, updated_cart} ->
          {:ok, repo().preload(updated_cart, items: [:product, :variant])}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Removes a referral code from a cart.

  ## Examples

      iex> remove_referral_code(cart_id)
      {:ok, %Cart{}}
  """
  def remove_referral_code(cart_id) do
    with {:ok, cart} <- get_cart(cart_id) do
      cart
      |> Cart.referral_changeset(%{referral_code_id: nil})
      |> repo().update()
      |> case do
        {:ok, updated_cart} ->
          {:ok, repo().preload(updated_cart, items: [:product, :variant])}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Recalculates cart totals.

  This function recalculates the subtotal, discount, shipping, tax, and grand total
  for the cart based on current items and applied coupons. When a destination
  address is provided, it will calculate shipping and tax costs using the
  configured calculators.

  ## Options

  - `:destination` - The shipping/tax address for calculations
  - `:shipping_calculator` - Override the configured shipping calculator
  - `:tax_calculator` - Override the configured tax calculator
  - `:shipping_method` - Specific shipping method to use

  ## Examples

      iex> recalculate_totals(cart_id)
      {:ok, %Cart{}}

      iex> recalculate_totals(cart_id, destination: address)
      {:ok, %Cart{}}

      iex> recalculate_totals(cart_id, destination: address, shipping_method: "expedited")
      {:ok, %Cart{}}
  """
  def recalculate_totals(cart_id, opts \\ []) do
    with {:ok, cart} <- get_cart(cart_id) do
      # Use Calculator module to compute all totals
      totals = Calculator.recalculate_totals(cart, opts)

      # Update cart with new totals
      cart
      |> Cart.totals_changeset(totals)
      |> repo().update()
      |> case do
        {:ok, updated_cart} ->
          # Update in-memory state if manager is running
          if Manager.alive?(cart_id) do
            Manager.update_cart(cart_id, updated_cart)
          end

          {:ok, repo().preload(updated_cart, :items, force: true)}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Gets available shipping methods for a destination.

  This function uses the configured ShippingCalculator behaviour to retrieve
  available shipping methods for the given destination address.

  ## Examples

      iex> get_shipping_methods(address)
      [%{id: "standard", name: "Standard Shipping", ...}]

      iex> get_shipping_methods(address, shipping_calculator: CustomCalculator)
      [%{id: "custom", name: "Custom Method", ...}]
  """
  def get_shipping_methods(destination, opts \\ []) do
    calculator = Keyword.get(opts, :shipping_calculator) || get_shipping_calculator()

    if calculator do
      calculator.get_available_methods(destination)
    else
      []
    end
  end

  @doc """
  Calculates shipping cost for a cart to a destination.

  This function uses the configured ShippingCalculator behaviour to calculate
  shipping costs based on cart contents and destination.

  ## Options

  - `:shipping_calculator` - Override the configured shipping calculator
  - `:method` - Specific shipping method to use

  ## Examples

      iex> calculate_shipping_cost(cart_id, address)
      {:ok, #Decimal<9.99>}

      iex> calculate_shipping_cost(cart_id, address, method: "expedited")
      {:ok, #Decimal<19.99>}
  """
  def calculate_shipping_cost(cart_id, destination, opts \\ []) do
    with {:ok, cart} <- get_cart(cart_id) do
      calculator = Keyword.get(opts, :shipping_calculator) || get_shipping_calculator()

      if calculator do
        calculator.calculate_shipping(cart, destination, opts)
      else
        {:ok, Decimal.new("0.00")}
      end
    end
  end

  @doc """
  Calculates tax for a cart based on destination.

  This function uses the configured TaxCalculator behaviour to calculate
  tax amounts based on cart contents and destination.

  ## Options

  - `:tax_calculator` - Override the configured tax calculator
  - `:customer_type` - "business" or "consumer"
  - `:tax_exempt` - Whether customer is tax exempt

  ## Examples

      iex> calculate_tax_cost(cart_id, address)
      {:ok, #Decimal<2.50>}

      iex> calculate_tax_cost(cart_id, address, tax_exempt: true)
      {:ok, #Decimal<0.00>}
  """
  def calculate_tax_cost(cart_id, destination, opts \\ []) do
    with {:ok, cart} <- get_cart(cart_id) do
      calculator = Keyword.get(opts, :tax_calculator) || get_tax_calculator()

      if calculator do
        calculator.calculate_tax(cart, destination, opts)
      else
        {:ok, Decimal.new("0.00")}
      end
    end
  end

  # Private Functions

  defp fetch_product(product_id) do
    try do
      product = Catalog.get_product!(product_id)
      {:ok, product}
    rescue
      Ecto.NoResultsError -> {:error, :product_not_found}
    end
  end

  defp find_cart_item(cart, product_id, variant_id) do
    Enum.find(cart.items, fn item ->
      item.product_id == product_id && item.variant_id == variant_id
    end)
  end

  defp get_cart_item(cart, item_id) do
    case Enum.find(cart.items, &(&1.id == item_id)) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  defp get_item_price(product, nil) do
    # Use product price if no variant
    {:ok, product.price}
  end

  defp get_item_price(product, variant_id) do
    # Get variant price
    case Catalog.get_variant(variant_id) do
      {:ok, variant} ->
        {:ok, variant.price}

      {:error, _} ->
        # Fall back to product price if variant not found
        {:ok, product.price}
    end
  end

  defp recalculate_and_broadcast(cart_id) do
    {:ok, cart} = recalculate_totals(cart_id)
    Events.broadcast_cart_updated(cart)
    cart
  end

  defp get_shipping_calculator do
    Application.get_env(:mercato, :shipping_calculator)
  end

  defp get_tax_calculator do
    Application.get_env(:mercato, :tax_calculator)
  end

  defp repo, do: Mercato.repo()
end
