defmodule Mercato.Orders do
  @moduledoc """
  The Orders context.

  This module provides the public API for managing orders, including
  creating orders from carts, updating order status, and handling
  order lifecycle operations.

  ## Features

  - Order creation from cart contents
  - Order status management with audit trail
  - Order cancellation and refunds
  - Real-time event broadcasting
  - Integration with inventory management

  ## Usage

      # Create an order from a cart
      {:ok, order} = Mercato.Orders.create_order_from_cart(cart_id, %{
        billing_address: %{...},
        shipping_address: %{...},
        payment_method: "credit_card"
      })

      # Update order status
      {:ok, order} = Mercato.Orders.update_status(order_id, "processing")

      # Cancel an order
      {:ok, order} = Mercato.Orders.cancel_order(order_id, "Customer request")

      # Refund an order
      {:ok, order} = Mercato.Orders.refund_order(order_id, amount, "Defective product")

      # Get order by ID
      {:ok, order} = Mercato.Orders.get_order!(order_id)
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mercato
  alias Mercato.Orders.{Order, OrderItem, OrderStatusHistory}
  alias Mercato.Cart
  alias Mercato.Catalog
  alias Mercato.Events
  alias Mercato.Referrals

  @doc """
  Gets an order by ID.

  Returns the order with preloaded items and status history.

  ## Examples

      iex> get_order!(order_id)
      %Order{}

      iex> get_order!("non-existent")
      ** (Ecto.NoResultsError)
  """
  def get_order!(order_id) do
    Order
    |> repo().get!(order_id)
    |> repo().preload([:items, :status_history])
  end

  @doc """
  Gets an order by ID, returning {:ok, order} or {:error, :not_found}.

  ## Examples

      iex> get_order(order_id)
      {:ok, %Order{}}

      iex> get_order("non-existent")
      {:error, :not_found}
  """
  def get_order(order_id) do
    case repo().get(Order, order_id) do
      nil ->
        {:error, :not_found}

      order ->
        order = repo().preload(order, [:items, :status_history])
        {:ok, order}
    end
  end

  @doc """
  Lists orders with optional filtering.

  ## Options

  - `:user_id` - Filter by user ID
  - `:status` - Filter by order status
  - `:limit` - Limit number of results (default: 50)
  - `:offset` - Offset for pagination (default: 0)
  - `:order_by` - Order by field (default: :inserted_at)
  - `:order_direction` - Order direction (default: :desc)

  ## Examples

      iex> list_orders()
      [%Order{}, ...]

      iex> list_orders(user_id: user_id, status: "completed")
      [%Order{}, ...]

      iex> list_orders(limit: 10, offset: 20)
      [%Order{}, ...]
  """
  def list_orders(opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by, :inserted_at)
    order_direction = Keyword.get(opts, :order_direction, :desc)

    query =
      from o in Order,
        order_by: [{^order_direction, field(o, ^order_by)}],
        limit: ^limit,
        offset: ^offset

    query =
      if user_id do
        from o in query, where: o.user_id == ^user_id
      else
        query
      end

    query =
      if status do
        from o in query, where: o.status == ^status
      else
        query
      end

    repo().all(query)
    |> repo().preload([:items, :status_history])
  end

  @doc """
  Creates an order from a cart.

  This function converts a cart into an order, copying all cart items
  and totals. The cart is marked as "converted" after successful order creation.
  If payment details are provided, it will process the payment through the
  configured payment gateway.

  ## Required Attributes

  - `:billing_address` - Customer billing address map
  - `:payment_method` - Payment method used

  ## Optional Attributes

  - `:shipping_address` - Customer shipping address (defaults to billing_address)
  - `:customer_notes` - Optional notes from customer
  - `:payment_details` - Payment information for gateway processing
  - `:payment_transaction_id` - External payment processor transaction ID (if payment processed externally)
  - `:process_payment` - Whether to process payment through gateway (default: true)

  ## Examples

      iex> create_order_from_cart(cart_id, %{
      ...>   billing_address: %{
      ...>     line1: "123 Main St",
      ...>     city: "Anytown",
      ...>     state: "CA",
      ...>     postal_code: "12345",
      ...>     country: "US"
      ...>   },
      ...>   payment_method: "credit_card",
      ...>   payment_details: %{token: "tok_123"}
      ...> })
      {:ok, %Order{}}

      iex> create_order_from_cart("non-existent", %{})
      {:error, :cart_not_found}
  """
  def create_order_from_cart(cart_id, attrs) do
    result =
      repo().transaction(fn ->
        with {:ok, cart} <- Cart.get_cart(cart_id),
             :ok <- validate_cart_not_empty(cart),
             {:ok, order_number} <- generate_order_number(),
             :ok <- reserve_inventory_for_cart(cart),
             {:ok, payment_result} <- process_payment_if_requested(cart, attrs),
             {:ok, order} <- create_order_from_cart_data(cart, order_number, attrs, payment_result),
             {:ok, _order_items} <- create_order_items_from_cart(order, cart),
             {:ok, _status_history} <- create_initial_status_history(order),
             {:ok, _updated_cart} <- mark_cart_as_converted(cart) do
          repo().preload(order, [:items, :status_history])
        else
          {:error, reason} ->
            repo().rollback(reason)
        end
      end)

    case result do
      {:ok, order} ->
        Events.broadcast_order_created(order)
        {:ok, order}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates an order's status.

  This function updates the order status and creates a status history entry
  for audit trail purposes.

  ## Examples

      iex> update_status(order_id, "processing")
      {:ok, %Order{}}

      iex> update_status(order_id, "invalid_status")
      {:error, %Ecto.Changeset{}}

      iex> update_status("non-existent", "processing")
      {:error, :not_found}
  """
  def update_status(order_id, new_status, opts \\ []) do
    changed_by = Keyword.get(opts, :changed_by)
    notes = Keyword.get(opts, :notes)

    repo().transaction(fn ->
      with {:ok, order} <- get_order(order_id) do
        old_status = order.status

        # Update order status
        case order
             |> Order.status_changeset(%{status: new_status})
             |> repo().update() do
          {:ok, updated_order} ->
            # Create status history entry
            {:ok, _history} =
              create_status_history_entry(order_id, old_status, new_status, changed_by, notes)

            # Handle status-specific logic
            handle_status_change(updated_order, old_status, new_status)

            # Broadcast status change event
            Events.broadcast_order_status_changed(updated_order, old_status, new_status)

            repo().preload(updated_order, [:items, :status_history], force: true)

          {:error, changeset} ->
            repo().rollback(changeset)
        end
      else
        {:error, reason} ->
          repo().rollback(reason)
      end
    end)
  end

  @doc """
  Cancels an order.

  This function sets the order status to "cancelled" and releases any
  reserved inventory back to stock.

  ## Examples

      iex> cancel_order(order_id, "Customer request")
      {:ok, %Order{}}

      iex> cancel_order("non-existent", "reason")
      {:error, :not_found}
  """
  def cancel_order(order_id, reason, opts \\ []) do
    changed_by = Keyword.get(opts, :changed_by)

    with {:ok, order} <- get_order(order_id) do
      if order.status in ~w(pending processing) do
        case update_status(order_id, "cancelled", changed_by: changed_by, notes: reason) do
          {:ok, cancelled_order} ->
            # Release inventory
            release_inventory_for_order(cancelled_order)

            {:ok, cancelled_order}

          {:error, reason} ->
            {:error, reason}
        end
      else
        {:error, :cannot_cancel_order}
      end
    end
  end

  @doc """
  Refunds an order or partial amount.

  This function sets the order status to "refunded" and optionally
  releases inventory back to stock for the refunded amount.

  ## Examples

      iex> refund_order(order_id, Decimal.new("50.00"), "Defective product")
      {:ok, %Order{}}

      iex> refund_order(order_id, order.grand_total, "Full refund")
      {:ok, %Order{}}
  """
  def refund_order(order_id, amount, reason, opts \\ []) do
    changed_by = Keyword.get(opts, :changed_by)
    release_inventory = Keyword.get(opts, :release_inventory, true)

    with {:ok, order} <- get_order(order_id) do
      if order.status in ~w(completed processing) do
        # Determine if this is a full or partial refund
        is_full_refund = Decimal.equal?(amount, order.grand_total)
        new_status = if is_full_refund, do: "refunded", else: order.status

        notes = "#{reason} - Refund amount: #{amount}"

        case update_status(order_id, new_status, changed_by: changed_by, notes: notes) do
          {:ok, refunded_order} ->
            # Release inventory if requested and full refund
            if release_inventory && is_full_refund do
              release_inventory_for_order(refunded_order)
            end

            {:ok, refunded_order}

          {:error, reason} ->
            {:error, reason}
        end
      else
        {:error, :cannot_refund_order}
      end
    end
  end

  @doc """
  Processes a payment for an order.

  This function integrates with the configured PaymentGateway behaviour to
  authorize and capture payment for the order amount.

  ## Options

  - `:payment_gateway` - Override the configured payment gateway
  - `:authorize_only` - Only authorize payment, don't capture (default: false)

  ## Examples

      iex> process_payment(order, %{token: "tok_123"})
      {:ok, %{transaction_id: "txn_123", status: "succeeded"}}

      iex> process_payment(order, %{token: "invalid"})
      {:error, :payment_failed}
  """
  def process_payment(order, payment_details, opts \\ []) do
    gateway = Keyword.get(opts, :payment_gateway) || get_payment_gateway()
    authorize_only = Keyword.get(opts, :authorize_only, false)

    if gateway do
      case gateway.authorize(order.grand_total, payment_details, opts) do
        {:ok, transaction_id} ->
          if authorize_only do
            {:ok, %{transaction_id: transaction_id, status: "authorized"}}
          else
            case gateway.capture(transaction_id, order.grand_total, opts) do
              {:ok, capture_details} ->
                {:ok, Map.put(capture_details, :transaction_id, transaction_id)}

              {:error, reason} ->
                {:error, {:capture_failed, reason}}
            end
          end

        {:error, reason} ->
          {:error, {:authorization_failed, reason}}
      end
    else
      {:error, :no_payment_gateway_configured}
    end
  end

  @doc """
  Processes a refund for an order through the payment gateway.

  ## Examples

      iex> process_refund(order, Decimal.new("50.00"), reason: "customer_request")
      {:ok, %{refund_id: "ref_123", status: "succeeded"}}

      iex> process_refund(order, Decimal.new("50.00"))
      {:error, :no_payment_gateway_configured}
  """
  def process_refund(order, amount, opts \\ []) do
    gateway = Keyword.get(opts, :payment_gateway) || get_payment_gateway()

    if gateway && order.payment_transaction_id do
      gateway.refund(order.payment_transaction_id, amount, opts)
    else
      {:error, :no_payment_gateway_configured}
    end
  end

  # Private Functions

  defp process_payment_if_requested(cart, attrs) do
    process_payment = get_attr(attrs, :process_payment, true)
    payment_details = get_attr(attrs, :payment_details)

    cond do
      not process_payment ->
        {:ok, nil}

      is_nil(payment_details) ->
        {:ok, nil}

      true ->
        # Create a temporary order-like structure for payment processing
        temp_order = %{grand_total: cart.grand_total}

        case process_payment_for_cart(temp_order, payment_details) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp process_payment_for_cart(cart_data, payment_details, opts \\ []) do
    gateway = Keyword.get(opts, :payment_gateway) || get_payment_gateway()

    if gateway do
      case gateway.authorize(cart_data.grand_total, payment_details, opts) do
        {:ok, transaction_id} ->
          case gateway.capture(transaction_id, cart_data.grand_total, opts) do
            {:ok, capture_details} ->
              {:ok, Map.put(capture_details, :transaction_id, transaction_id)}

            {:error, reason} ->
              {:error, {:capture_failed, reason}}
          end

        {:error, reason} ->
          {:error, {:authorization_failed, reason}}
      end
    else
      {:ok, nil} # No payment gateway configured, proceed without payment
    end
  end

  defp determine_initial_status(payment_result) do
    case payment_result do
      %{status: "succeeded"} -> "processing"
      %{status: "authorized"} -> "pending"
      nil -> "pending"
      _ -> "failed"
    end
  end

  defp get_transaction_id(payment_result) do
    case payment_result do
      %{transaction_id: transaction_id} -> transaction_id
      _ -> nil
    end
  end

  defp get_payment_gateway do
    Application.get_env(:mercato, :payment_gateway)
  end

  defp generate_order_number do
    # Generate a unique order number with timestamp and random suffix
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")
    order_number = "ORD-#{timestamp}-#{random}"

    # Check if order number already exists (very unlikely but possible)
    case repo().get_by(Order, order_number: order_number) do
      nil -> {:ok, order_number}
      _existing -> generate_order_number() # Retry with new number
    end
  end

  defp create_order_from_cart_data(cart, order_number, attrs, payment_result) do
    # Set shipping address to billing address if not provided
    billing_address = get_attr(attrs, :billing_address)
    shipping_address = get_attr(attrs, :shipping_address, billing_address)

    order_attrs =
      attrs
      |> Map.put(:order_number, order_number)
      |> Map.put(:user_id, cart.user_id)
      |> Map.put(:status, determine_initial_status(payment_result))
      |> Map.put(:subtotal, cart.subtotal)
      |> Map.put(:discount_total, cart.discount_total)
      |> Map.put(:shipping_total, cart.shipping_total)
      |> Map.put(:tax_total, cart.tax_total)
      |> Map.put(:grand_total, cart.grand_total)
      |> Map.put(:applied_coupon_id, cart.applied_coupon_id)
      |> Map.put(:referral_code_id, cart.referral_code_id)
      |> Map.put(:shipping_address, shipping_address)
      |> Map.put(:payment_transaction_id, get_transaction_id(payment_result))

    %Order{}
    |> Order.create_changeset(order_attrs)
    |> repo().insert()
  end

  defp create_order_items_from_cart(order, cart) do
    order_items =
      Enum.map(cart.items, fn cart_item ->
        # Create product snapshot
        product_snapshot = create_product_snapshot(cart_item)

        %{
          order_id: order.id,
          product_id: cart_item.product_id,
          variant_id: cart_item.variant_id,
          quantity: cart_item.quantity,
          unit_price: cart_item.unit_price,
          total_price: cart_item.total_price,
          product_snapshot: product_snapshot,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      end)

    case repo().insert_all(OrderItem, order_items, returning: true) do
      {_count, items} -> {:ok, items}
      error -> {:error, error}
    end
  end

  defp create_product_snapshot(cart_item) do
    product = cart_item.product
    variant = cart_item.variant

    base_snapshot = %{
      "name" => product.name,
      "sku" => product.sku,
      "description" => product.description,
      "product_type" => product.product_type,
      "images" => product.images
    }

    if variant do
      base_snapshot
      |> Map.put("variant_sku", variant.sku)
      |> Map.put("attributes", variant.attributes)
    else
      base_snapshot
    end
  end

  defp create_initial_status_history(order) do
    %OrderStatusHistory{}
    |> OrderStatusHistory.changeset(%{
      order_id: order.id,
      from_status: nil,
      to_status: order.status,
      notes: "Order created",
      changed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> repo().insert()
  end

  defp reserve_inventory_for_cart(cart) do
    Enum.reduce_while(cart.items, :ok, fn item, :ok ->
      opts = if item.variant_id, do: [variant_id: item.variant_id], else: []

      case Catalog.reserve_stock(item.product_id, item.quantity, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_cart_not_empty(cart) do
    if Enum.empty?(cart.items) do
      {:error, :empty_cart}
    else
      :ok
    end
  end

  defp get_attr(attrs, key, default \\ nil) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp create_status_history_entry(order_id, from_status, to_status, changed_by, notes) do
    %OrderStatusHistory{}
    |> OrderStatusHistory.changeset(%{
      order_id: order_id,
      from_status: from_status,
      to_status: to_status,
      notes: notes,
      changed_by: changed_by,
      changed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> repo().insert()
  end

  defp mark_cart_as_converted(cart) do
    cart
    |> Cart.Cart.status_changeset(%{status: "converted"})
    |> repo().update()
  end

  defp handle_status_change(order, old_status, new_status) do
    case {old_status, new_status} do
      {_, "cancelled"} ->
        # Inventory release handled in cancel_order/3
        :ok

      {_, "refunded"} ->
        # Inventory release handled in refund_order/4
        :ok

      {_, "completed"} ->
        # Order completed - could trigger fulfillment processes
        Logger.info("Order #{order.order_number} completed")

        # Create referral commission if order has referral code
        if order.referral_code_id do
          create_referral_commission(order)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp reserve_inventory_for_order(order) do
    # Reserve stock for each order item
    order = repo().preload(order, :items)

    Enum.each(order.items, fn item ->
      opts = if item.variant_id, do: [variant_id: item.variant_id], else: []

      case Catalog.reserve_stock(item.product_id, item.quantity, opts) do
        :ok ->
          Logger.debug("Reserved #{item.quantity} units of product #{item.product_id} for order #{order.order_number}")
          Events.broadcast_stock_reserved(item.product_id, item.quantity)

        {:error, :insufficient_stock} ->
          Logger.warning("Insufficient stock for product #{item.product_id} in order #{order.order_number}")

        {:error, reason} ->
          Logger.error("Failed to reserve stock for product #{item.product_id}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Creates an order from a subscription renewal.

  This function creates an order for a subscription billing cycle,
  including the subscription product as a line item.

  ## Examples

      iex> create_order_from_subscription(subscription, %{
      ...>   subtotal: Decimal.new("29.99"),
      ...>   grand_total: Decimal.new("29.99"),
      ...>   payment_method: "subscription_billing"
      ...> })
      {:ok, %Order{}}
  """
  def create_order_from_subscription(subscription, attrs) do
    repo().transaction(fn ->
      with {:ok, order_number} <- generate_order_number(),
           {:ok, order} <- create_order_from_subscription_data(subscription, order_number, attrs),
           {:ok, _order_item} <- create_order_item_from_subscription(order, subscription) do
        # Broadcast order created event
        Events.broadcast_order_created(order)

        # Return order with preloaded associations
        repo().preload(order, [:items, :status_history])
      else
        {:error, reason} ->
          repo().rollback(reason)
      end
    end)
  end

  defp release_inventory_for_order(order) do
    # Release stock for each order item
    order = repo().preload(order, :items)

    Enum.each(order.items, fn item ->
      opts = if item.variant_id, do: [variant_id: item.variant_id], else: []

      case Catalog.release_stock(item.product_id, item.quantity, opts) do
        :ok ->
          Logger.debug("Released #{item.quantity} units of product #{item.product_id} for order #{order.order_number}")
          Events.broadcast_stock_released(item.product_id, item.quantity)

        {:error, reason} ->
          Logger.error("Failed to release stock for product #{item.product_id}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp create_order_from_subscription_data(subscription, order_number, attrs) do
    order_attrs =
      attrs
      |> Map.put(:order_number, order_number)
      |> Map.put(:user_id, subscription.user_id)
      |> Map.put(:status, "pending")

    %Order{}
    |> Order.create_changeset(order_attrs)
    |> repo().insert()
  end

  defp create_order_item_from_subscription(order, subscription) do
    # Get product information for the subscription
    product = repo().get!(Mercato.Catalog.Product, subscription.product_id)
    variant =
      if subscription.variant_id,
        do: repo().get(Mercato.Catalog.ProductVariant, subscription.variant_id),
        else: nil

    # Create product snapshot
    product_snapshot = create_subscription_product_snapshot(product, variant)

    %OrderItem{}
    |> OrderItem.changeset(%{
      order_id: order.id,
      product_id: subscription.product_id,
      variant_id: subscription.variant_id,
      quantity: 1, # Subscriptions are typically quantity 1
      unit_price: subscription.billing_amount,
      total_price: subscription.billing_amount,
      product_snapshot: product_snapshot
    })
    |> repo().insert()
  end

  defp create_subscription_product_snapshot(product, variant) do
    base_snapshot = %{
      "name" => product.name,
      "sku" => product.sku,
      "description" => product.description,
      "product_type" => product.product_type,
      "images" => product.images,
      "subscription_billing" => true
    }

    if variant do
      base_snapshot
      |> Map.put("variant_sku", variant.sku)
      |> Map.put("attributes", variant.attributes)
    else
      base_snapshot
    end
  end

  defp create_referral_commission(order) do
    # Get the referral code to find the code string
    case repo().get(Mercato.Referrals.ReferralCode, order.referral_code_id) do
      nil ->
        Logger.warning("Referral code not found for order #{order.order_number}")
        :ok

      referral_code ->
        case Referrals.track_conversion(referral_code.code, order.id) do
          {:ok, commission} ->
            Logger.info("Created referral commission #{commission.id} for order #{order.order_number}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to create referral commission for order #{order.order_number}: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp repo, do: Mercato.repo()
end
