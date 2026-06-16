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

  alias Ecto.Multi
  alias Mercato
  alias Mercato.Orders.{NumberGenerator, Order, OrderItem, OrderStatusHistory}
  alias Mercato.Cart
  alias Mercato.Catalog
  alias Mercato.Coupons
  alias Mercato.Events
  alias Mercato.Referrals
  alias Mercato.Runtime
  alias Mercato.Telemetry

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
      from(o in Order,
        order_by: [{^order_direction, field(o, ^order_by)}],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if user_id do
        from(o in query, where: o.user_id == ^user_id)
      else
        query
      end

    query =
      if status do
        from(o in query, where: o.status == ^status)
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
  - `:idempotency_key` - Unique key used to safely deduplicate client retries
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
    attrs = normalize_attrs(attrs)
    idempotency_key = get_idempotency_key(attrs)

    case get_order_by_idempotency_key(idempotency_key, cart_id) do
      {:ok, order} ->
        {:ok, order}

      :not_found ->
        do_create_order_from_cart(cart_id, attrs, idempotency_key)
    end
  end

  defp do_create_order_from_cart(cart_id, attrs, idempotency_key) do
    result =
      Multi.new()
      |> Multi.run(:cart, fn _repo, _changes -> Cart.get_cart(cart_id) end)
      |> Multi.run(:validate_cart, fn _repo, %{cart: cart} ->
        case validate_cart_for_order(cart) do
          :ok -> {:ok, :ok}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Multi.run(:order_number, fn _repo, _changes -> NumberGenerator.generate() end)
      |> Multi.run(:reserve_inventory, fn _repo, %{cart: cart} ->
        case reserve_inventory_for_cart(cart) do
          :ok -> {:ok, :ok}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Multi.run(:order, fn _repo, %{cart: cart, order_number: order_number} ->
        create_order_from_cart_data(cart, order_number, attrs, idempotency_key)
      end)
      |> Multi.run(:order_items, fn _repo, %{order: order, cart: cart} ->
        create_order_items_from_cart(order, cart)
      end)
      |> Multi.run(:payment_result, fn _repo, %{cart: cart} ->
        process_payment_if_requested(cart, attrs)
      end)
      |> Multi.run(:order_with_payment, fn _repo,
                                           %{order: order, payment_result: payment_result} ->
        apply_payment_result(order, payment_result)
      end)
      |> Multi.run(:status_history, fn _repo, %{order_with_payment: order} ->
        create_initial_status_history(order)
      end)
      |> Multi.run(:coupon_usage, fn _repo, %{cart: cart, order_with_payment: order} ->
        case record_coupon_usage_if_needed(cart, order) do
          :ok -> {:ok, :ok}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Multi.run(:updated_cart, fn _repo, %{cart: cart} ->
        mark_cart_as_converted(cart)
      end)
      |> Multi.run(:preloaded_order, fn _repo, %{order_with_payment: order} ->
        {:ok, repo().preload(order, [:items, :status_history])}
      end)
      |> repo().transaction()

    case result do
      {:ok, %{preloaded_order: order}} ->
        Events.broadcast_order_created(order)

        Telemetry.execute([:order, :create, :stop], %{count: 1}, %{
          order_id: order.id,
          user_id: order.user_id
        })

        {:ok, order}

      {:error, :order, %Ecto.Changeset{} = changeset, _changes}
      when not is_nil(idempotency_key) ->
        handle_idempotency_conflict(changeset, idempotency_key, cart_id)

      {:error, _step, reason, _changes} ->
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

    with {:ok, order} <- get_order(order_id) do
      old_status = order.status

      result =
        Multi.new()
        |> Multi.update(:order, Order.status_changeset(order, %{status: new_status}))
        |> Multi.run(:history, fn _repo, %{order: updated_order} ->
          create_status_history_entry(
            order_id,
            old_status,
            updated_order.status,
            changed_by,
            notes
          )
        end)
        |> Multi.run(:status_change_logic, fn _repo, %{order: updated_order} ->
          :ok = handle_status_change(updated_order, old_status, updated_order.status)
          {:ok, :ok}
        end)
        |> Multi.run(:preloaded_order, fn _repo, %{order: updated_order} ->
          {:ok, repo().preload(updated_order, [:items, :status_history], force: true)}
        end)
        |> repo().transaction()

      case result do
        {:ok, %{preloaded_order: updated_order}} ->
          Events.broadcast_order_status_changed(updated_order, old_status, updated_order.status)
          {:ok, updated_order}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
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
    authorize_only = Keyword.get(opts, :authorize_only, false)

    with {:ok, gateway} <- Runtime.fetch_payment_gateway(opts),
         {:ok, transaction_id} <-
           authorize_payment(gateway, order.grand_total, payment_details, opts) do
      if authorize_only do
        {:ok, %{transaction_id: transaction_id, status: "authorized"}}
      else
        capture_payment(gateway, transaction_id, order.grand_total, opts)
      end
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
    with {:ok, gateway} <- Runtime.fetch_payment_gateway(opts),
         transaction_id when is_binary(transaction_id) <- order.payment_transaction_id do
      Telemetry.execute([:payment, :refund, :start], %{amount: amount}, %{order_id: order.id})

      case gateway.refund(transaction_id, amount, opts) do
        {:ok, refund_details} ->
          Telemetry.execute([:payment, :refund, :stop], %{amount: amount}, %{
            order_id: order.id,
            refund_id: refund_details[:refund_id]
          })

          {:ok, refund_details}

        {:error, reason} ->
          Telemetry.execute([:payment, :refund, :exception], %{amount: amount}, %{
            order_id: order.id,
            reason: reason
          })

          {:error, {:refund_failed, reason}}
      end
    else
      {:error, :payment_gateway_not_configured} = error -> error
      {:error, :dummy_payment_gateway_not_allowed} = error -> error
      nil -> {:error, :missing_payment_transaction_id}
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
    with {:ok, gateway} <- Runtime.fetch_payment_gateway(opts),
         {:ok, transaction_id} <-
           authorize_payment(gateway, cart_data.grand_total, payment_details, opts) do
      capture_payment(gateway, transaction_id, cart_data.grand_total, opts)
    else
      {:error, :payment_gateway_not_configured} = error -> error
      {:error, :dummy_payment_gateway_not_allowed} = error -> error
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

  defp create_order_from_cart_data(cart, order_number, attrs, idempotency_key) do
    # Set shipping address to billing address if not provided
    billing_address = get_attr(attrs, :billing_address)
    shipping_address = get_attr(attrs, :shipping_address, billing_address)

    # Buyer-supplied fields only.
    client_attrs = %{
      billing_address: billing_address,
      shipping_address: shipping_address,
      customer_notes: get_attr(attrs, :customer_notes),
      payment_method: get_attr(attrs, :payment_method)
    }

    # Server-computed/internal fields. Totals, status, coupon and referral come from
    # the server-side cart, never from the request — so a client cannot tamper with them.
    server_attrs = %{
      order_number: order_number,
      source_cart_id: cart.id,
      user_id: cart.user_id,
      status: "pending",
      subtotal: cart.subtotal,
      discount_total: cart.discount_total,
      shipping_total: cart.shipping_total,
      tax_total: cart.tax_total,
      duties_total: cart.duties_total,
      grand_total: cart.grand_total,
      applied_coupon_id: cart.applied_coupon_id,
      referral_code_id: cart.referral_code_id,
      payment_transaction_id: get_attr(attrs, :payment_transaction_id),
      idempotency_key: idempotency_key
    }

    %Order{}
    |> Order.create_changeset(client_attrs, server_attrs)
    |> repo().insert()
  end

  defp apply_payment_result(order, nil), do: {:ok, order}

  defp apply_payment_result(order, payment_result) do
    update_attrs = %{
      status: determine_initial_status(payment_result),
      payment_transaction_id: get_transaction_id(payment_result)
    }

    order
    |> Ecto.Changeset.change(update_attrs)
    |> repo().update()
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

  defp validate_cart_for_order(cart) do
    cond do
      cart.status != "active" ->
        {:error, :inactive_cart}

      Enum.empty?(cart.items) ->
        {:error, :empty_cart}

      true ->
        :ok
    end
  end

  defp get_attr(attrs, key, default \\ nil) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(attrs) when is_list(attrs), do: Map.new(attrs)

  defp get_idempotency_key(attrs) do
    attrs
    |> get_attr(:idempotency_key)
    |> normalize_idempotency_key()
  end

  defp normalize_idempotency_key(key) when is_binary(key) do
    case String.trim(key) do
      "" -> nil
      normalized_key -> normalized_key
    end
  end

  defp normalize_idempotency_key(_key), do: nil

  defp get_order_by_idempotency_key(nil, _cart_id), do: :not_found

  defp get_order_by_idempotency_key(idempotency_key, cart_id) do
    case repo().get_by(Order, idempotency_key: idempotency_key, source_cart_id: cart_id) do
      nil ->
        :not_found

      order ->
        {:ok, repo().preload(order, [:items, :status_history])}
    end
  end

  defp handle_idempotency_conflict(changeset, idempotency_key, cart_id) do
    if idempotency_key_unique_conflict?(changeset) do
      case get_order_by_idempotency_key(idempotency_key, cart_id) do
        {:ok, order} -> {:ok, order}
        :not_found -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp idempotency_key_unique_conflict?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:idempotency_key, {_message, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp authorize_payment(gateway, amount, payment_details, opts) do
    Telemetry.execute([:payment, :authorize, :start], %{amount: amount}, %{})

    case gateway.authorize(amount, payment_details, opts) do
      {:ok, transaction_id} ->
        Telemetry.execute([:payment, :authorize, :stop], %{amount: amount}, %{
          transaction_id: transaction_id
        })

        {:ok, transaction_id}

      {:error, reason} ->
        Telemetry.execute([:payment, :authorize, :exception], %{amount: amount}, %{reason: reason})

        {:error, {:authorization_failed, reason}}
    end
  end

  defp capture_payment(gateway, transaction_id, amount, opts) do
    Telemetry.execute([:payment, :capture, :start], %{amount: amount}, %{
      transaction_id: transaction_id
    })

    case gateway.capture(transaction_id, amount, opts) do
      {:ok, capture_details} ->
        Telemetry.execute([:payment, :capture, :stop], %{amount: amount}, %{
          transaction_id: transaction_id
        })

        {:ok, Map.put(capture_details, :transaction_id, transaction_id)}

      {:error, reason} ->
        Telemetry.execute([:payment, :capture, :exception], %{amount: amount}, %{
          transaction_id: transaction_id,
          reason: reason
        })

        {:error, {:capture_failed, reason}}
    end
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

  defp record_coupon_usage_if_needed(%{applied_coupon_id: nil}, _order), do: :ok

  defp record_coupon_usage_if_needed(cart, order) do
    case repo().get(Coupons.Coupon, cart.applied_coupon_id) do
      nil ->
        {:error, :coupon_not_found}

      coupon ->
        case Coupons.record_coupon_usage(coupon, order.id, cart.user_id) do
          {:ok, _usage} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
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
  def create_order_from_subscription(subscription, attrs, opts \\ []) do
    broadcast? = Keyword.get(opts, :broadcast?, true)

    result =
      Multi.new()
      |> Multi.run(:order_number, fn _repo, _changes -> NumberGenerator.generate() end)
      |> Multi.run(:order, fn _repo, %{order_number: order_number} ->
        create_order_from_subscription_data(subscription, order_number, attrs)
      end)
      |> Multi.run(:order_item, fn _repo, %{order: order} ->
        create_order_item_from_subscription(order, subscription)
      end)
      |> Multi.run(:preloaded_order, fn _repo, %{order: order} ->
        {:ok, repo().preload(order, [:items, :status_history])}
      end)
      |> repo().transaction()

    case result do
      {:ok, %{preloaded_order: order}} ->
        if broadcast?, do: Events.broadcast_order_created(order)
        {:ok, order}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp release_inventory_for_order(order) do
    # Release stock for each order item
    order = repo().preload(order, :items)

    Enum.each(order.items, fn item ->
      opts = if item.variant_id, do: [variant_id: item.variant_id], else: []

      case Catalog.release_stock(item.product_id, item.quantity, opts) do
        :ok ->
          Logger.debug(
            "Released #{item.quantity} units of product #{item.product_id} for order #{order.order_number}"
          )

          Events.broadcast_stock_released(item.product_id, item.quantity)

        {:error, reason} ->
          Logger.error(
            "Failed to release stock for product #{item.product_id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  defp create_order_from_subscription_data(subscription, order_number, attrs) do
    # Subscription renewals are entirely server-generated; the only buyer-style field
    # is the payment method. Totals/status/identifiers go through server_attrs.
    client_attrs =
      Map.take(attrs, [:billing_address, :shipping_address, :customer_notes, :payment_method])

    server_attrs =
      attrs
      |> Map.drop([:billing_address, :shipping_address, :customer_notes, :payment_method])
      |> Map.put(:order_number, order_number)
      |> Map.put(:user_id, subscription.user_id)
      |> Map.put(:status, "pending")

    %Order{}
    |> Order.create_changeset(client_attrs, server_attrs)
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
      # Subscriptions are typically quantity 1
      quantity: 1,
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
            Logger.info(
              "Created referral commission #{commission.id} for order #{order.order_number}"
            )

            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to create referral commission for order #{order.order_number}: #{inspect(reason)}"
            )

            :ok
        end
    end
  end

  defp repo, do: Mercato.repo()
end
