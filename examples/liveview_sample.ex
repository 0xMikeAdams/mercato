# Sample LiveView Integration
# Example of how to integrate Mercato with Phoenix LiveView

defmodule YourAppWeb.CartLive do
  use YourAppWeb, :live_view
  alias Mercato.{Cart, Events}

  def mount(_params, %{"cart_token" => cart_token}, socket) do
    if connected?(socket) do
      Events.subscribe_to_cart(cart_token)
    end

    {:ok, cart} = Cart.get_cart_by_token(cart_token)
    {:ok, assign(socket, cart: cart)}
  end

  def handle_info({:cart_updated, cart}, socket) do
    {:noreply, assign(socket, cart: cart)}
  end

  def handle_event("add_item", %{"product_id" => product_id}, socket) do
    {:ok, cart} = Cart.add_item(socket.assigns.cart.id, product_id, 1)
    {:noreply, assign(socket, cart: cart)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h2>Shopping Cart</h2>
      <div>Items: <%= length(@cart.items) %></div>
      <div>Total: $<%= @cart.grand_total %></div>
    </div>
    """
  end
end
