# LiveView Cart with Real-time Updates Example

This example demonstrates a complete shopping cart implementation with real-time updates using Phoenix LiveView and Mercato.

## Cart LiveView

```elixir
defmodule MyStoreWeb.CartLive.Index do
  use MyStoreWeb, :live_view
  alias Mercato.{Cart, Events, Catalog, Coupons}

  @impl true
  def mount(_params, session, socket) do
    cart_token = get_cart_token(session)
    
    if connected?(socket) do
      Events.subscribe_to_cart(cart_token)
    end

    {:ok, cart} = Cart.get_cart_by_token(cart_token)

    socket =
      socket
      |> assign(:cart, cart)
      |> assign(:cart_token, cart_token)
      |> assign(:loading, false)
      |> assign(:coupon_code, "")
      |> assign(:coupon_error, nil)
      |> assign(:updating_item, nil)

    {:ok, socket}
  end

  # Handle real-time cart updates
  @impl true
  def handle_info({:cart_updated, cart}, socket) do
    socket =
      socket
      |> assign(:cart, cart)
      |> assign(:updating_item, nil)
      |> clear_flash()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:cart_cleared, _cart_id}, socket) do
    {:ok, empty_cart} = Cart.get_cart_by_token(socket.assigns.cart_token)
    
    socket =
      socket
      |> assign(:cart, empty_cart)
      |> put_flash(:info, "Cart has been cleared")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:cart_item_added, cart, item}, socket) do
    product_name = item.product.name
    
    socket =
      socket
      |> assign(:cart, cart)
      |> put_flash(:info, "#{product_name} added to cart")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:cart_item_removed, cart, _item_id}, socket) do
    socket =
      socket
      |> assign(:cart, cart)
      |> put_flash(:info, "Item removed from cart")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:cart_coupon_applied, cart, coupon}, socket) do
    socket =
      socket
      |> assign(:cart, cart)
      |> assign(:coupon_code, "")
      |> assign(:coupon_error, nil)
      |> put_flash(:info, "Coupon '#{coupon.code}' applied successfully!")

    {:noreply, socket}
  end

  # Handle user interactions
  @impl true
  def handle_event("update_quantity", %{"item_id" => item_id, "quantity" => quantity_str}, socket) do
    quantity = String.to_integer(quantity_str)
    
    socket = assign(socket, :updating_item, item_id)

    case Cart.update_item_quantity(socket.assigns.cart_token, item_id, quantity) do
      {:ok, _cart} ->
        # Cart will be updated via PubSub message
        {:noreply, socket}

      {:error, :insufficient_stock} ->
        socket =
          socket
          |> assign(:updating_item, nil)
          |> put_flash(:error, "Not enough stock available")

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:updating_item, nil)
          |> put_flash(:error, "Could not update quantity: #{reason}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_item", %{"item_id" => item_id}, socket) do
    case Cart.remove_item(socket.assigns.cart_token, item_id) do
      {:ok, _cart} ->
        # Cart will be updated via PubSub message
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Could not remove item: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_cart", _params, socket) do
    case Cart.clear_cart(socket.assigns.cart_token) do
      {:ok, _cart} ->
        # Cart will be updated via PubSub message
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Could not clear cart: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("apply_coupon", %{"coupon" => %{"code" => code}}, socket) do
    case Cart.apply_coupon(socket.assigns.cart_token, code) do
      {:ok, _cart} ->
        # Cart will be updated via PubSub message
        {:noreply, socket}

      {:error, reason} ->
        error_message = format_coupon_error(reason)
        
        socket =
          socket
          |> assign(:coupon_error, error_message)
          |> put_flash(:error, error_message)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_coupon", _params, socket) do
    case Cart.remove_coupon(socket.assigns.cart_token) do
      {:ok, _cart} ->
        # Cart will be updated via PubSub message
        socket = put_flash(socket, :info, "Coupon removed")
        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Could not remove coupon: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_coupon_code", %{"coupon" => %{"code" => code}}, socket) do
    socket =
      socket
      |> assign(:coupon_code, code)
      |> assign(:coupon_error, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("continue_shopping", _params, socket) do
    {:noreply, redirect(socket, to: Routes.product_index_path(socket, :index))}
  end

  @impl true
  def handle_event("proceed_to_checkout", _params, socket) do
    if Enum.empty?(socket.assigns.cart.cart_items) do
      socket = put_flash(socket, :error, "Your cart is empty")
      {:noreply, socket}
    else
      {:noreply, redirect(socket, to: Routes.checkout_index_path(socket, :index))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="cart-page">
      <div class="cart-header">
        <h1>Shopping Cart</h1>
        <div class="cart-summary">
          <%= if Enum.empty?(@cart.cart_items) do %>
            <span>Your cart is empty</span>
          <% else %>
            <span><%= cart_item_count(@cart) %> items</span>
          <% end %>
        </div>
      </div>

      <%= if Enum.empty?(@cart.cart_items) do %>
        <.empty_cart />
      <% else %>
        <div class="cart-content">
          <div class="cart-items">
            <.cart_items_table cart={@cart} updating_item={@updating_item} />
          </div>

          <div class="cart-sidebar">
            <.coupon_section 
              coupon_code={@coupon_code} 
              coupon_error={@coupon_error}
              applied_coupon={@cart.applied_coupon}
            />
            
            <.cart_totals cart={@cart} />
            
            <.cart_actions />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Component: Empty cart state
  defp empty_cart(assigns) do
    ~H"""
    <div class="empty-cart">
      <div class="empty-cart-icon">🛒</div>
      <h2>Your cart is empty</h2>
      <p>Looks like you haven't added any items to your cart yet.</p>
      <button phx-click="continue_shopping" class="btn btn-primary">
        Continue Shopping
      </button>
    </div>
    """
  end

  # Component: Cart items table
  defp cart_items_table(assigns) do
    ~H"""
    <div class="cart-items-table">
      <div class="table-header">
        <div class="col-product">Product</div>
        <div class="col-price">Price</div>
        <div class="col-quantity">Quantity</div>
        <div class="col-total">Total</div>
        <div class="col-actions">Actions</div>
      </div>

      <%= for item <- @cart.cart_items do %>
        <div class="cart-item" id={"cart-item-#{item.id}"}>
          <div class="col-product">
            <div class="product-info">
              <%= if item.product.images && length(item.product.images) > 0 do %>
                <img src={hd(item.product.images)} alt={item.product.name} class="product-image" />
              <% else %>
                <div class="product-image placeholder">No Image</div>
              <% end %>
              
              <div class="product-details">
                <h4 class="product-name">
                  <.link navigate={Routes.product_show_path(@socket, :show, item.product.slug)}>
                    <%= item.product.name %>
                  </.link>
                </h4>
                
                <%= if item.variant do %>
                  <div class="variant-info">
                    <%= format_variant_attributes(item.variant.attributes) %>
                  </div>
                <% end %>
                
                <div class="product-sku">SKU: <%= item.product.sku %></div>
              </div>
            </div>
          </div>

          <div class="col-price">
            $<%= item.unit_price %>
          </div>

          <div class="col-quantity">
            <div class="quantity-controls">
              <input 
                type="number" 
                value={item.quantity}
                min="1"
                max={get_max_quantity(item)}
                phx-change="update_quantity"
                phx-value-item_id={item.id}
                class="quantity-input"
                disabled={@updating_item == item.id}
              />
              
              <%= if @updating_item == item.id do %>
                <div class="updating-spinner">⟳</div>
              <% end %>
            </div>
            
            <div class="stock-info">
              <%= case get_stock_status(item) do %>
                <% {:in_stock, available} when available <= 5 -> %>
                  <span class="low-stock">Only <%= available %> left</span>
                <% {:in_stock, _} -> %>
                  <span class="in-stock">In stock</span>
                <% :out_of_stock -> %>
                  <span class="out-of-stock">Out of stock</span>
              <% end %>
            </div>
          </div>

          <div class="col-total">
            <strong>$<%= item.total_price %></strong>
          </div>

          <div class="col-actions">
            <button 
              phx-click="remove_item" 
              phx-value-item_id={item.id}
              class="btn btn-sm btn-danger"
              data-confirm="Are you sure you want to remove this item?"
            >
              Remove
            </button>
          </div>
        </div>
      <% end %>

      <div class="cart-actions-row">
        <button phx-click="clear_cart" class="btn btn-outline" data-confirm="Are you sure you want to clear your cart?">
          Clear Cart
        </button>
        
        <button phx-click="continue_shopping" class="btn btn-outline">
          Continue Shopping
        </button>
      </div>
    </div>
    """
  end

  # Component: Coupon section
  defp coupon_section(assigns) do
    ~H"""
    <div class="coupon-section">
      <h3>Coupon Code</h3>
      
      <%= if @applied_coupon do %>
        <div class="applied-coupon">
          <div class="coupon-info">
            <span class="coupon-code">✓ <%= @applied_coupon.code %></span>
            <span class="coupon-description">
              <%= format_coupon_description(@applied_coupon) %>
            </span>
          </div>
          <button phx-click="remove_coupon" class="btn btn-sm btn-outline">
            Remove
          </button>
        </div>
      <% else %>
        <.form let={f} for={:coupon} phx-submit="apply_coupon" phx-change="update_coupon_code">
          <div class="coupon-input-group">
            <%= text_input f, :code, 
                  value: @coupon_code,
                  placeholder: "Enter coupon code",
                  class: "coupon-input #{if @coupon_error, do: "error", else: ""}" %>
            <%= submit "Apply", class: "btn btn-primary", disabled: @coupon_code == "" %>
          </div>
          
          <%= if @coupon_error do %>
            <div class="coupon-error"><%= @coupon_error %></div>
          <% end %>
        </.form>
      <% end %>
    </div>
    """
  end

  # Component: Cart totals
  defp cart_totals(assigns) do
    ~H"""
    <div class="cart-totals">
      <h3>Order Summary</h3>
      
      <div class="totals-breakdown">
        <div class="total-line">
          <span>Subtotal:</span>
          <span>$<%= @cart.subtotal %></span>
        </div>
        
        <%= if @cart.discount_total && Decimal.gt?(@cart.discount_total, 0) do %>
          <div class="total-line discount">
            <span>Discount:</span>
            <span>-$<%= @cart.discount_total %></span>
          </div>
        <% end %>
        
        <%= if @cart.shipping_total && Decimal.gt?(@cart.shipping_total, 0) do %>
          <div class="total-line">
            <span>Shipping:</span>
            <span>$<%= @cart.shipping_total %></span>
          </div>
        <% end %>
        
        <%= if @cart.tax_total && Decimal.gt?(@cart.tax_total, 0) do %>
          <div class="total-line">
            <span>Tax:</span>
            <span>$<%= @cart.tax_total %></span>
          </div>
        <% end %>
        
        <div class="total-line grand-total">
          <span><strong>Total:</strong></span>
          <span><strong>$<%= @cart.grand_total %></strong></span>
        </div>
      </div>
    </div>
    """
  end

  # Component: Cart actions
  defp cart_actions(assigns) do
    ~H"""
    <div class="cart-actions">
      <button phx-click="proceed_to_checkout" class="btn btn-primary btn-large">
        Proceed to Checkout
      </button>
      
      <div class="security-badges">
        <div class="security-badge">🔒 Secure Checkout</div>
        <div class="security-badge">✓ SSL Encrypted</div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp get_cart_token(session) do
    session["cart_token"] || "default-cart-token"
  end

  defp cart_item_count(cart) do
    Enum.sum(Enum.map(cart.cart_items, & &1.quantity))
  end

  defp format_variant_attributes(attributes) when is_map(attributes) do
    attributes
    |> Enum.map(fn {key, value} -> "#{String.capitalize(key)}: #{value}" end)
    |> Enum.join(", ")
  end

  defp format_variant_attributes(_), do: ""

  defp get_max_quantity(item) do
    available_stock = 
      if item.variant do
        item.variant.stock_quantity
      else
        item.product.stock_quantity
      end
    
    min(available_stock, 99) # Limit to 99 per item
  end

  defp get_stock_status(item) do
    available_stock = 
      if item.variant do
        item.variant.stock_quantity
      else
        item.product.stock_quantity
      end

    if available_stock > 0 do
      {:in_stock, available_stock}
    else
      :out_of_stock
    end
  end

  defp format_coupon_description(coupon) do
    case coupon.discount_type do
      "percentage" ->
        "#{coupon.discount_value}% off"
      
      "fixed_cart" ->
        "$#{coupon.discount_value} off your order"
      
      "fixed_product" ->
        "$#{coupon.discount_value} off each item"
      
      "free_shipping" ->
        "Free shipping"
      
      _ ->
        "Discount applied"
    end
  end

  defp format_coupon_error(:coupon_not_found), do: "Coupon code not found"
  defp format_coupon_error(:coupon_expired), do: "This coupon has expired"
  defp format_coupon_error(:coupon_not_active), do: "This coupon is not yet active"
  defp format_coupon_error(:usage_limit_exceeded), do: "This coupon has reached its usage limit"
  defp format_coupon_error(:minimum_spend_not_met), do: "Minimum spend requirement not met"
  defp format_coupon_error(:product_not_eligible), do: "No eligible products in cart"
  defp format_coupon_error(reason), do: "Coupon error: #{reason}"
end
```

## Mini Cart Component

```elixir
defmodule MyStoreWeb.Components.MiniCart do
  use MyStoreWeb, :live_component
  alias Mercato.{Cart, Events}

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{cart_token: cart_token} = assigns, socket) do
    if connected?(socket) do
      Events.subscribe_to_cart(cart_token)
    end

    {:ok, cart} = Cart.get_cart_by_token(cart_token)

    socket =
      socket
      |> assign(assigns)
      |> assign(:cart, cart)
      |> assign(:show_dropdown, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_dropdown, !socket.assigns.show_dropdown)}
  end

  @impl true
  def handle_event("close_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_dropdown, false)}
  end

  @impl true
  def handle_event("remove_item", %{"item_id" => item_id}, socket) do
    case Cart.remove_item(socket.assigns.cart_token, item_id) do
      {:ok, _cart} ->
        # Cart will be updated via PubSub
        {:noreply, socket}

      {:error, _reason} ->
        # Handle error silently in mini cart
        {:noreply, socket}
    end
  end

  # Handle real-time cart updates
  @impl true
  def handle_info({:cart_updated, cart}, socket) do
    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def handle_info({:cart_cleared, _cart_id}, socket) do
    {:ok, empty_cart} = Cart.get_cart_by_token(socket.assigns.cart_token)
    {:noreply, assign(socket, :cart, empty_cart)}
  end

  @impl true
  def handle_info({:cart_item_added, cart, _item}, socket) do
    socket =
      socket
      |> assign(:cart, cart)
      |> assign(:show_dropdown, true) # Auto-show dropdown when item added

    {:noreply, socket}
  end

  @impl true
  def handle_info({:cart_item_removed, cart, _item_id}, socket) do
    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mini-cart" id={"mini-cart-#{@id}"}>
      <button 
        phx-click="toggle_dropdown" 
        phx-target={@myself}
        class="cart-trigger"
      >
        <span class="cart-icon">🛒</span>
        <span class="cart-count"><%= cart_item_count(@cart) %></span>
        <span class="cart-total">$<%= @cart.grand_total %></span>
      </button>

      <%= if @show_dropdown do %>
        <div class="cart-dropdown" phx-click-away="close_dropdown" phx-target={@myself}>
          <div class="dropdown-header">
            <h4>Shopping Cart</h4>
            <button phx-click="close_dropdown" phx-target={@myself} class="close-btn">×</button>
          </div>

          <div class="dropdown-content">
            <%= if Enum.empty?(@cart.cart_items) do %>
              <div class="empty-cart-message">
                <p>Your cart is empty</p>
              </div>
            <% else %>
              <div class="cart-items-list">
                <%= for item <- @cart.cart_items do %>
                  <div class="mini-cart-item">
                    <div class="item-image">
                      <%= if item.product.images && length(item.product.images) > 0 do %>
                        <img src={hd(item.product.images)} alt={item.product.name} />
                      <% else %>
                        <div class="placeholder">📦</div>
                      <% end %>
                    </div>
                    
                    <div class="item-details">
                      <div class="item-name"><%= item.product.name %></div>
                      <div class="item-quantity">Qty: <%= item.quantity %></div>
                      <div class="item-price">$<%= item.total_price %></div>
                    </div>
                    
                    <button 
                      phx-click="remove_item" 
                      phx-value-item_id={item.id}
                      phx-target={@myself}
                      class="remove-btn"
                      title="Remove item"
                    >
                      ×
                    </button>
                  </div>
                <% end %>
              </div>

              <div class="dropdown-footer">
                <div class="cart-total">
                  <strong>Total: $<%= @cart.grand_total %></strong>
                </div>
                
                <div class="cart-actions">
                  <.link navigate={Routes.cart_index_path(@socket, :index)} class="btn btn-outline btn-sm">
                    View Cart
                  </.link>
                  
                  <.link navigate={Routes.checkout_index_path(@socket, :index)} class="btn btn-primary btn-sm">
                    Checkout
                  </.link>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp cart_item_count(cart) do
    Enum.sum(Enum.map(cart.cart_items, & &1.quantity))
  end
end
```

## Usage in Layout

```elixir
# In your layout template (e.g., app.html.heex)

<header class="site-header">
  <div class="header-content">
    <.link navigate={Routes.page_index_path(@conn, :index)} class="logo">
      My Store
    </.link>
    
    <nav class="main-nav">
      <.link navigate={Routes.product_index_path(@conn, :index)}>Products</.link>
      <.link navigate={Routes.page_about_path(@conn, :about)}>About</.link>
      <.link navigate={Routes.page_contact_path(@conn, :contact)}>Contact</.link>
    </nav>
    
    <div class="header-actions">
      <%= if assigns[:cart_token] do %>
        <.live_component 
          module={MyStoreWeb.Components.MiniCart} 
          id="header-mini-cart"
          cart_token={@cart_token}
        />
      <% end %>
    </div>
  </div>
</header>
```

## CSS Styles

```css
/* Cart Page Styles */
.cart-page {
  max-width: 1200px;
  margin: 0 auto;
  padding: 20px;
}

.cart-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 30px;
  padding-bottom: 20px;
  border-bottom: 1px solid #eee;
}

.cart-content {
  display: grid;
  grid-template-columns: 2fr 1fr;
  gap: 40px;
}

.cart-items-table {
  background: white;
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.table-header {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr 1fr 1fr;
  gap: 15px;
  padding: 20px;
  background: #f8f9fa;
  font-weight: bold;
  border-bottom: 1px solid #eee;
}

.cart-item {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr 1fr 1fr;
  gap: 15px;
  padding: 20px;
  border-bottom: 1px solid #eee;
  align-items: center;
}

.product-info {
  display: flex;
  gap: 15px;
  align-items: center;
}

.product-image {
  width: 80px;
  height: 80px;
  object-fit: cover;
  border-radius: 4px;
}

.product-image.placeholder {
  background: #f5f5f5;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #999;
}

.product-details h4 {
  margin: 0 0 5px 0;
  font-size: 16px;
}

.product-details a {
  text-decoration: none;
  color: #333;
}

.product-details a:hover {
  color: #007cba;
}

.variant-info, .product-sku {
  font-size: 12px;
  color: #666;
  margin: 2px 0;
}

.quantity-controls {
  display: flex;
  align-items: center;
  gap: 10px;
}

.quantity-input {
  width: 80px;
  padding: 8px;
  border: 1px solid #ddd;
  border-radius: 4px;
  text-align: center;
}

.updating-spinner {
  animation: spin 1s linear infinite;
  font-size: 18px;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.stock-info {
  font-size: 12px;
  margin-top: 5px;
}

.in-stock { color: #27ae60; }
.low-stock { color: #f39c12; font-weight: bold; }
.out-of-stock { color: #e74c3c; font-weight: bold; }

.cart-actions-row {
  padding: 20px;
  display: flex;
  gap: 15px;
  background: #f8f9fa;
}

/* Cart Sidebar */
.cart-sidebar {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.coupon-section, .cart-totals, .cart-actions {
  background: white;
  padding: 20px;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.coupon-section h3, .cart-totals h3 {
  margin: 0 0 15px 0;
  font-size: 18px;
}

.applied-coupon {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px;
  background: #e8f5e8;
  border-radius: 4px;
}

.coupon-code {
  font-weight: bold;
  color: #27ae60;
}

.coupon-description {
  font-size: 12px;
  color: #666;
  display: block;
}

.coupon-input-group {
  display: flex;
  gap: 10px;
}

.coupon-input {
  flex: 1;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
}

.coupon-input.error {
  border-color: #e74c3c;
}

.coupon-error {
  color: #e74c3c;
  font-size: 12px;
  margin-top: 5px;
}

.totals-breakdown {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.total-line {
  display: flex;
  justify-content: space-between;
  padding: 5px 0;
}

.total-line.discount {
  color: #27ae60;
}

.total-line.grand-total {
  border-top: 1px solid #eee;
  padding-top: 15px;
  margin-top: 10px;
  font-size: 18px;
}

.security-badges {
  display: flex;
  flex-direction: column;
  gap: 5px;
  margin-top: 15px;
}

.security-badge {
  font-size: 12px;
  color: #666;
  text-align: center;
}

/* Empty Cart */
.empty-cart {
  text-align: center;
  padding: 60px 20px;
}

.empty-cart-icon {
  font-size: 64px;
  margin-bottom: 20px;
}

/* Mini Cart Styles */
.mini-cart {
  position: relative;
}

.cart-trigger {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: none;
  border: 1px solid #ddd;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
}

.cart-trigger:hover {
  background: #f5f5f5;
}

.cart-count {
  background: #007cba;
  color: white;
  border-radius: 50%;
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: bold;
}

.cart-dropdown {
  position: absolute;
  top: 100%;
  right: 0;
  width: 350px;
  background: white;
  border: 1px solid #ddd;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
  z-index: 1000;
  margin-top: 5px;
}

.dropdown-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 15px 20px;
  border-bottom: 1px solid #eee;
}

.dropdown-header h4 {
  margin: 0;
  font-size: 16px;
}

.close-btn {
  background: none;
  border: none;
  font-size: 20px;
  cursor: pointer;
  color: #666;
}

.dropdown-content {
  max-height: 400px;
  overflow-y: auto;
}

.empty-cart-message {
  padding: 40px 20px;
  text-align: center;
  color: #666;
}

.cart-items-list {
  padding: 10px 0;
}

.mini-cart-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 20px;
  border-bottom: 1px solid #f5f5f5;
}

.mini-cart-item:last-child {
  border-bottom: none;
}

.mini-cart-item .item-image {
  width: 40px;
  height: 40px;
}

.mini-cart-item .item-image img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 4px;
}

.mini-cart-item .placeholder {
  width: 100%;
  height: 100%;
  background: #f5f5f5;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  font-size: 12px;
}

.item-details {
  flex: 1;
}

.item-name {
  font-weight: 500;
  font-size: 14px;
  margin-bottom: 2px;
}

.item-quantity, .item-price {
  font-size: 12px;
  color: #666;
}

.remove-btn {
  background: none;
  border: none;
  color: #999;
  cursor: pointer;
  font-size: 16px;
  padding: 5px;
}

.remove-btn:hover {
  color: #e74c3c;
}

.dropdown-footer {
  padding: 15px 20px;
  border-top: 1px solid #eee;
  background: #f8f9fa;
}

.dropdown-footer .cart-total {
  margin-bottom: 15px;
  text-align: center;
}

.cart-actions {
  display: flex;
  gap: 10px;
}

.cart-actions .btn {
  flex: 1;
  text-align: center;
  text-decoration: none;
}

/* Button Styles */
.btn {
  padding: 10px 20px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-weight: 500;
  text-decoration: none;
  display: inline-block;
  text-align: center;
  transition: all 0.2s;
}

.btn-primary {
  background: #007cba;
  color: white;
}

.btn-primary:hover {
  background: #005a87;
}

.btn-outline {
  background: white;
  color: #007cba;
  border: 1px solid #007cba;
}

.btn-outline:hover {
  background: #007cba;
  color: white;
}

.btn-danger {
  background: #e74c3c;
  color: white;
}

.btn-danger:hover {
  background: #c0392b;
}

.btn-sm {
  padding: 6px 12px;
  font-size: 12px;
}

.btn-large {
  padding: 15px 30px;
  font-size: 16px;
  width: 100%;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* Responsive Design */
@media (max-width: 768px) {
  .cart-content {
    grid-template-columns: 1fr;
    gap: 20px;
  }
  
  .table-header {
    display: none;
  }
  
  .cart-item {
    grid-template-columns: 1fr;
    gap: 10px;
  }
  
  .cart-dropdown {
    width: 300px;
  }
}
```

This comprehensive example demonstrates a fully functional shopping cart with real-time updates, including a main cart page and a mini cart component that can be used throughout the application.
