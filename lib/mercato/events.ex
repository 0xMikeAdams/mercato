defmodule Mercato.Events do
  @moduledoc """
  Event broadcasting and subscription helpers for Mercato.

  This module provides a centralized interface for publishing and subscribing to
  real-time events throughout the Mercato system using Phoenix PubSub.

  ## Event Topics

  Mercato publishes events on the following topics:

  - `"cart:{cart_id}"` - Cart-specific events (item added, updated, cleared)
  - `"order:{order_id}"` - Order-specific events (status changes, updates)
  - `"inventory:{product_id}"` - Inventory updates for products
  - `"subscription:{subscription_id}"` - Subscription lifecycle events
  - `"referral:{referral_code_id}"` - Referral tracking events

  ## Event Types

  ### Cart Events

  - `{:cart_updated, cart}` - Cart contents or totals changed
  - `{:cart_cleared, cart_id}` - Cart was cleared
  - `{:cart_item_added, cart, item}` - Item added to cart
  - `{:cart_item_removed, cart, item_id}` - Item removed from cart
  - `{:cart_coupon_applied, cart, coupon}` - Coupon applied to cart

  ### Order Events

  - `{:order_created, order}` - New order created
  - `{:order_status_changed, order, old_status, new_status}` - Order status updated
  - `{:order_cancelled, order}` - Order cancelled
  - `{:order_refunded, order, amount}` - Order refunded

  ### Inventory Events

  - `{:stock_reserved, product_id, quantity}` - Stock reserved for order
  - `{:stock_released, product_id, quantity}` - Stock released (cancellation/refund)
  - `{:stock_updated, product_id, new_quantity}` - Stock quantity changed

  ### Subscription Events

  - `{:subscription_created, subscription}` - New subscription created
  - `{:subscription_renewed, subscription, order}` - Subscription renewed
  - `{:subscription_paused, subscription}` - Subscription paused
  - `{:subscription_resumed, subscription}` - Subscription resumed
  - `{:subscription_cancelled, subscription}` - Subscription cancelled

  ## Usage

  ### Publishing Events

      # Publish a cart update event
      Mercato.Events.broadcast_cart_updated(cart)

      # Publish an order status change
      Mercato.Events.broadcast_order_status_changed(order, :pending, :processing)

  ### Subscribing to Events

      # Subscribe to cart events in a LiveView
      def mount(_params, _session, socket) do
        cart_id = get_cart_id(socket)
        Mercato.Events.subscribe_to_cart(cart_id)
        {:ok, socket}
      end

      def handle_info({:cart_updated, cart}, socket) do
        {:noreply, assign(socket, :cart, cart)}
      end

      # Subscribe to order events
      def mount(%{"order_id" => order_id}, _session, socket) do
        Mercato.Events.subscribe_to_order(order_id)
        {:ok, socket}
      end

      def handle_info({:order_status_changed, order, _old, _new}, socket) do
        {:noreply, assign(socket, :order, order)}
      end
  """

  alias Phoenix.PubSub

  @pubsub Mercato.PubSub

  # Cart Events

  @doc """
  Subscribes the current process to cart events for the given cart ID.
  """
  def subscribe_to_cart(cart_id) do
    PubSub.subscribe(@pubsub, "cart:#{cart_id}")
  end

  @doc """
  Unsubscribes the current process from cart events for the given cart ID.
  """
  def unsubscribe_from_cart(cart_id) do
    PubSub.unsubscribe(@pubsub, "cart:#{cart_id}")
  end

  @doc """
  Broadcasts a cart updated event.
  """
  def broadcast_cart_updated(cart) do
    PubSub.broadcast(@pubsub, "cart:#{cart.id}", {:cart_updated, cart})
  end

  @doc """
  Broadcasts a cart cleared event.
  """
  def broadcast_cart_cleared(cart_id) do
    PubSub.broadcast(@pubsub, "cart:#{cart_id}", {:cart_cleared, cart_id})
  end

  @doc """
  Broadcasts a cart item added event.
  """
  def broadcast_cart_item_added(cart, item) do
    PubSub.broadcast(@pubsub, "cart:#{cart.id}", {:cart_item_added, cart, item})
  end

  @doc """
  Broadcasts a cart item removed event.
  """
  def broadcast_cart_item_removed(cart, item_id) do
    PubSub.broadcast(@pubsub, "cart:#{cart.id}", {:cart_item_removed, cart, item_id})
  end

  @doc """
  Broadcasts a cart coupon applied event.
  """
  def broadcast_cart_coupon_applied(cart, coupon) do
    PubSub.broadcast(@pubsub, "cart:#{cart.id}", {:cart_coupon_applied, cart, coupon})
  end

  # Order Events

  @doc """
  Subscribes the current process to order events for the given order ID.
  """
  def subscribe_to_order(order_id) do
    PubSub.subscribe(@pubsub, "order:#{order_id}")
  end

  @doc """
  Unsubscribes the current process from order events for the given order ID.
  """
  def unsubscribe_from_order(order_id) do
    PubSub.unsubscribe(@pubsub, "order:#{order_id}")
  end

  @doc """
  Broadcasts an order created event.
  """
  def broadcast_order_created(order) do
    PubSub.broadcast(@pubsub, "order:#{order.id}", {:order_created, order})
  end

  @doc """
  Broadcasts an order status changed event.
  """
  def broadcast_order_status_changed(order, old_status, new_status) do
    PubSub.broadcast(
      @pubsub,
      "order:#{order.id}",
      {:order_status_changed, order, old_status, new_status}
    )
  end

  @doc """
  Broadcasts an order cancelled event.
  """
  def broadcast_order_cancelled(order) do
    PubSub.broadcast(@pubsub, "order:#{order.id}", {:order_cancelled, order})
  end

  @doc """
  Broadcasts an order refunded event.
  """
  def broadcast_order_refunded(order, amount) do
    PubSub.broadcast(@pubsub, "order:#{order.id}", {:order_refunded, order, amount})
  end

  # Inventory Events

  @doc """
  Subscribes the current process to inventory events for the given product ID.
  """
  def subscribe_to_inventory(product_id) do
    PubSub.subscribe(@pubsub, "inventory:#{product_id}")
  end

  @doc """
  Unsubscribes the current process from inventory events for the given product ID.
  """
  def unsubscribe_from_inventory(product_id) do
    PubSub.unsubscribe(@pubsub, "inventory:#{product_id}")
  end

  @doc """
  Broadcasts a stock reserved event.
  """
  def broadcast_stock_reserved(product_id, quantity) do
    PubSub.broadcast(@pubsub, "inventory:#{product_id}", {:stock_reserved, product_id, quantity})
  end

  @doc """
  Broadcasts a stock released event.
  """
  def broadcast_stock_released(product_id, quantity) do
    PubSub.broadcast(@pubsub, "inventory:#{product_id}", {:stock_released, product_id, quantity})
  end

  @doc """
  Broadcasts a stock updated event.
  """
  def broadcast_stock_updated(product_id, new_quantity) do
    PubSub.broadcast(@pubsub, "inventory:#{product_id}", {:stock_updated, product_id, new_quantity})
  end

  # Subscription Events

  @doc """
  Subscribes the current process to subscription events for the given subscription ID.
  """
  def subscribe_to_subscription(subscription_id) do
    PubSub.subscribe(@pubsub, "subscription:#{subscription_id}")
  end

  @doc """
  Unsubscribes the current process from subscription events for the given subscription ID.
  """
  def unsubscribe_from_subscription(subscription_id) do
    PubSub.unsubscribe(@pubsub, "subscription:#{subscription_id}")
  end

  @doc """
  Broadcasts a subscription created event.
  """
  def broadcast_subscription_created(subscription) do
    PubSub.broadcast(@pubsub, "subscription:#{subscription.id}", {:subscription_created, subscription})
  end

  @doc """
  Broadcasts a subscription renewed event.
  """
  def broadcast_subscription_renewed(subscription, order) do
    PubSub.broadcast(
      @pubsub,
      "subscription:#{subscription.id}",
      {:subscription_renewed, subscription, order}
    )
  end

  @doc """
  Broadcasts a subscription paused event.
  """
  def broadcast_subscription_paused(subscription) do
    PubSub.broadcast(@pubsub, "subscription:#{subscription.id}", {:subscription_paused, subscription})
  end

  @doc """
  Broadcasts a subscription resumed event.
  """
  def broadcast_subscription_resumed(subscription) do
    PubSub.broadcast(@pubsub, "subscription:#{subscription.id}", {:subscription_resumed, subscription})
  end

  @doc """
  Broadcasts a subscription cancelled event.
  """
  def broadcast_subscription_cancelled(subscription) do
    PubSub.broadcast(@pubsub, "subscription:#{subscription.id}", {:subscription_cancelled, subscription})
  end

  # Referral Events

  @doc """
  Subscribes the current process to referral events for the given referral code ID.
  """
  def subscribe_to_referral(referral_code_id) do
    PubSub.subscribe(@pubsub, "referral:#{referral_code_id}")
  end

  @doc """
  Unsubscribes the current process from referral events for the given referral code ID.
  """
  def unsubscribe_from_referral(referral_code_id) do
    PubSub.unsubscribe(@pubsub, "referral:#{referral_code_id}")
  end

  @doc """
  Broadcasts a referral click event.
  """
  def broadcast_referral_click(referral_code_id, click_metadata) do
    PubSub.broadcast(@pubsub, "referral:#{referral_code_id}", {:referral_click, click_metadata})
  end

  @doc """
  Broadcasts a referral click tracked event.
  """
  def broadcast_referral_click_tracked(referral_code_id, click) do
    PubSub.broadcast(@pubsub, "referral:#{referral_code_id}", {:referral_click_tracked, click})
  end

  @doc """
  Broadcasts a referral conversion tracked event.
  """
  def broadcast_referral_conversion_tracked(referral_code_id, commission) do
    PubSub.broadcast(
      @pubsub,
      "referral:#{referral_code_id}",
      {:referral_conversion_tracked, commission}
    )
  end

  # LiveView Integration Helpers

  @doc """
  LiveView helper to subscribe to cart events and handle common patterns.

  This function should be called in your LiveView's mount/3 callback.
  It automatically subscribes to cart events and provides a standardized
  way to handle cart updates in LiveView.

  ## Usage

      defmodule MyAppWeb.CartLive do
        use Phoenix.LiveView
        alias Mercato.Events

        def mount(_params, %{"cart_token" => cart_token}, socket) do
          cart = Mercato.Cart.get_cart(cart_token)
          Events.subscribe_to_cart_liveview(cart.id, self())

          {:ok, assign(socket, cart: cart)}
        end

        # Handle cart events
        def handle_info({:cart_updated, cart}, socket) do
          {:noreply, assign(socket, :cart, cart)}
        end

        def handle_info({:cart_item_added, cart, _item}, socket) do
          # Show success message and update cart
          socket =
            socket
            |> put_flash(:info, "Item added to cart")
            |> assign(:cart, cart)

          {:noreply, socket}
        end

        def handle_info({:cart_cleared, _cart_id}, socket) do
          # Redirect to empty cart page or update UI
          {:noreply, redirect(socket, to: "/cart")}
        end
      end

  ## Parameters

  - `cart_id` - The cart ID to subscribe to
  - `pid` - The LiveView process PID (usually `self()`)

  ## Returns

  `:ok` on successful subscription
  """
  def subscribe_to_cart_liveview(cart_id, _pid \\ self()) do
    subscribe_to_cart(cart_id)

    # Store subscription info for cleanup
    Process.put({:mercato_subscriptions, :cart}, cart_id)

    :ok
  end

  @doc """
  LiveView helper to subscribe to order events and handle common patterns.

  This function should be called in your LiveView's mount/3 callback for
  order tracking pages, checkout confirmation, or admin order management.

  ## Usage

      defmodule MyAppWeb.OrderLive do
        use Phoenix.LiveView
        alias Mercato.Events

        def mount(%{"order_id" => order_id}, _session, socket) do
          order = Mercato.Orders.get_order!(order_id)
          Events.subscribe_to_order_liveview(order_id, self())

          {:ok, assign(socket, order: order)}
        end

        # Handle order events
        def handle_info({:order_status_changed, order, _old_status, _new_status}, socket) do
          # Show status change notification
          message = "Order status has been updated"

          socket =
            socket
            |> put_flash(:info, message)
            |> assign(:order, order)

          {:noreply, socket}
        end

        def handle_info({:order_cancelled, order}, socket) do
          socket =
            socket
            |> put_flash(:error, "Order has been cancelled")
            |> assign(:order, order)

          {:noreply, socket}
        end

        def handle_info({:order_refunded, order, _amount}, socket) do
          message = "Refund has been processed"

          socket =
            socket
            |> put_flash(:info, message)
            |> assign(:order, order)

          {:noreply, socket}
        end
      end

  ## Parameters

  - `order_id` - The order ID to subscribe to
  - `pid` - The LiveView process PID (usually `self()`)

  ## Returns

  `:ok` on successful subscription
  """
  def subscribe_to_order_liveview(order_id, _pid \\ self()) do
    subscribe_to_order(order_id)

    # Store subscription info for cleanup
    Process.put({:mercato_subscriptions, :order}, order_id)

    :ok
  end

  @doc """
  LiveView helper to subscribe to inventory events for product pages.

  Useful for product detail pages that need to show real-time stock updates.

  ## Usage

      defmodule MyAppWeb.ProductLive do
        use Phoenix.LiveView
        alias Mercato.Events

        def mount(%{"product_id" => product_id}, _session, socket) do
          product = Mercato.Catalog.get_product!(product_id)
          Events.subscribe_to_inventory_liveview(product_id, self())

          {:ok, assign(socket, product: product)}
        end

        def handle_info({:stock_updated, product_id, new_quantity}, socket) do
          # Update product stock display
          product = %{socket.assigns.product | stock_quantity: new_quantity}

          socket =
            socket
            |> assign(:product, product)
            |> maybe_show_stock_alert(new_quantity)

          {:noreply, socket}
        end

        defp maybe_show_stock_alert(socket, quantity) when quantity <= 5 do
          put_flash(socket, :warning, "Only \#{quantity} items left in stock!")
        end

        defp maybe_show_stock_alert(socket, _quantity), do: socket
      end

  ## Parameters

  - `product_id` - The product ID to subscribe to
  - `pid` - The LiveView process PID (usually `self()`)

  ## Returns

  `:ok` on successful subscription
  """
  def subscribe_to_inventory_liveview(product_id, _pid \\ self()) do
    subscribe_to_inventory(product_id)

    # Store subscription info for cleanup
    Process.put({:mercato_subscriptions, :inventory}, product_id)

    :ok
  end

  @doc """
  LiveView helper to subscribe to subscription events for customer dashboards.

  ## Usage

      defmodule MyAppWeb.SubscriptionLive do
        use Phoenix.LiveView
        alias Mercato.Events

        def mount(%{"subscription_id" => subscription_id}, _session, socket) do
          subscription = Mercato.Subscriptions.get_subscription!(subscription_id)
          Events.subscribe_to_subscription_liveview(subscription_id, self())

          {:ok, assign(socket, subscription: subscription)}
        end

        def handle_info({:subscription_renewed, subscription, order}, socket) do
          message = "Subscription renewed successfully. Order #\#{order.order_number} created."

          socket =
            socket
            |> put_flash(:info, message)
            |> assign(:subscription, subscription)

          {:noreply, socket}
        end

        def handle_info({:subscription_paused, subscription}, socket) do
          socket =
            socket
            |> put_flash(:info, "Subscription has been paused")
            |> assign(:subscription, subscription)

          {:noreply, socket}
        end
      end

  ## Parameters

  - `subscription_id` - The subscription ID to subscribe to
  - `pid` - The LiveView process PID (usually `self()`)

  ## Returns

  `:ok` on successful subscription
  """
  def subscribe_to_subscription_liveview(subscription_id, _pid \\ self()) do
    subscribe_to_subscription(subscription_id)

    # Store subscription info for cleanup
    Process.put({:mercato_subscriptions, :subscription}, subscription_id)

    :ok
  end

  @doc """
  Cleans up all Mercato subscriptions for the current process.

  This function should be called in your LiveView's terminate/2 callback
  to ensure proper cleanup of PubSub subscriptions.

  ## Usage

      defmodule MyAppWeb.CartLive do
        use Phoenix.LiveView
        alias Mercato.Events

        def mount(_params, %{"cart_token" => cart_token}, socket) do
          cart = Mercato.Cart.get_cart(cart_token)
          Events.subscribe_to_cart_liveview(cart.id)

          {:ok, assign(socket, cart: cart)}
        end

        def terminate(_reason, _socket) do
          Events.cleanup_liveview_subscriptions()
          :ok
        end
      end

  ## Returns

  `:ok` after cleaning up all subscriptions
  """
  def cleanup_liveview_subscriptions do
    # Clean up cart subscriptions
    case Process.get({:mercato_subscriptions, :cart}) do
      nil -> :ok
      cart_id -> unsubscribe_from_cart(cart_id)
    end

    # Clean up order subscriptions
    case Process.get({:mercato_subscriptions, :order}) do
      nil -> :ok
      order_id -> unsubscribe_from_order(order_id)
    end

    # Clean up inventory subscriptions
    case Process.get({:mercato_subscriptions, :inventory}) do
      nil -> :ok
      product_id -> unsubscribe_from_inventory(product_id)
    end

    # Clean up subscription subscriptions
    case Process.get({:mercato_subscriptions, :subscription}) do
      nil -> :ok
      subscription_id -> unsubscribe_from_subscription(subscription_id)
    end

    # Clean up referral subscriptions
    case Process.get({:mercato_subscriptions, :referral}) do
      nil -> :ok
      referral_code_id -> unsubscribe_from_referral(referral_code_id)
    end

    :ok
  end

  @doc """
  Convenience function to subscribe to multiple event types at once.

  Useful for complex LiveViews that need to listen to multiple event streams.

  ## Usage

      def mount(params, session, socket) do
        cart = get_cart(session)
        order = get_current_order(params)

        Events.subscribe_to_multiple_liveview([
          {:cart, cart.id},
          {:order, order.id},
          {:inventory, cart.items |> Enum.map(& &1.product_id)}
        ])

        {:ok, assign(socket, cart: cart, order: order)}
      end

  ## Parameters

  - `subscriptions` - List of tuples in format `{:type, id}` or `{:type, [ids]}`

  Valid types: `:cart`, `:order`, `:inventory`, `:subscription`, `:referral`

  ## Returns

  `:ok` after setting up all subscriptions
  """
  def subscribe_to_multiple_liveview(subscriptions) do
    Enum.each(subscriptions, fn
      {:cart, cart_id} -> subscribe_to_cart_liveview(cart_id)
      {:order, order_id} -> subscribe_to_order_liveview(order_id)
      {:inventory, product_id} when is_binary(product_id) -> subscribe_to_inventory_liveview(product_id)
      {:inventory, product_ids} when is_list(product_ids) ->
        Enum.each(product_ids, &subscribe_to_inventory_liveview/1)
      {:subscription, subscription_id} -> subscribe_to_subscription_liveview(subscription_id)
      {:referral, referral_code_id} -> subscribe_to_referral(referral_code_id)
    end)

    :ok
  end
end
