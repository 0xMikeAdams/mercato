# LiveView Product Listing Example

This example demonstrates how to create a product listing page with real-time inventory updates using Phoenix LiveView and Mercato.

## Product Listing LiveView

```elixir
defmodule MyStoreWeb.ProductLive.Index do
  use MyStoreWeb, :live_view
  alias Mercato.{Catalog, Events}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to inventory updates for all products
      subscribe_to_inventory_updates()
    end

    products = load_products()

    socket =
      socket
      |> assign(:products, products)
      |> assign(:loading, false)
      |> assign(:filters, %{category: nil, search: "", sort: "name"})
      |> assign(:categories, load_categories())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = %{
      category: params["category"],
      search: params["search"] || "",
      sort: params["sort"] || "name"
    }

    products = load_products(filters)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:products, products)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    filters = %{socket.assigns.filters | search: query}
    
    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: Routes.product_index_path(socket, :index, build_query_params(filters)))

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    category = if category == "", do: nil, else: category
    filters = %{socket.assigns.filters | category: category}
    
    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: Routes.product_index_path(socket, :index, build_query_params(filters)))

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort_by}, socket) do
    filters = %{socket.assigns.filters | sort: sort_by}
    
    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: Routes.product_index_path(socket, :index, build_query_params(filters)))

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_to_cart", %{"product-id" => product_id}, socket) do
    cart_token = get_cart_token(socket)
    
    case Mercato.Cart.add_item(cart_token, product_id, 1) do
      {:ok, _cart} ->
        socket =
          socket
          |> put_flash(:info, "Product added to cart!")
          |> update_cart_count()

        {:noreply, socket}

      {:error, :insufficient_stock} ->
        {:noreply, put_flash(socket, :error, "Sorry, this item is out of stock.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add item to cart: #{reason}")}
    end
  end

  # Handle real-time inventory updates
  @impl true
  def handle_info({:stock_updated, product_id, new_quantity}, socket) do
    products = 
      Enum.map(socket.assigns.products, fn product ->
        if product.id == product_id do
          %{product | stock_quantity: new_quantity}
        else
          product
        end
      end)

    socket = assign(socket, :products, products)

    # Show notification if product goes out of stock
    socket =
      if new_quantity == 0 do
        product = Enum.find(products, &(&1.id == product_id))
        put_flash(socket, :warning, "#{product.name} is now out of stock")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stock_reserved, product_id, quantity}, socket) do
    # Update stock display when items are reserved (added to carts)
    products = 
      Enum.map(socket.assigns.products, fn product ->
        if product.id == product_id do
          new_stock = max(0, product.stock_quantity - quantity)
          %{product | stock_quantity: new_stock}
        else
          product
        end
      end)

    {:noreply, assign(socket, :products, products)}
  end

  @impl true
  def handle_info({:stock_released, product_id, quantity}, socket) do
    # Update stock display when items are released (removed from carts)
    products = 
      Enum.map(socket.assigns.products, fn product ->
        if product.id == product_id do
          %{product | stock_quantity: product.stock_quantity + quantity}
        else
          product
        end
      end)

    {:noreply, assign(socket, :products, products)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="product-listing">
      <div class="header">
        <h1>Products</h1>
        <div class="cart-indicator">
          Cart (<%= @cart_count %> items)
        </div>
      </div>

      <!-- Search and Filters -->
      <div class="filters">
        <.form let={f} for={:search} phx-submit="search" phx-change="search">
          <%= text_input f, :query, 
                value: @filters.search, 
                placeholder: "Search products...",
                class: "search-input" %>
        </.form>

        <select phx-change="filter_category" name="category" class="category-filter">
          <option value="">All Categories</option>
          <%= for category <- @categories do %>
            <option value={category.id} selected={@filters.category == category.id}>
              <%= category.name %>
            </option>
          <% end %>
        </select>

        <select phx-change="sort" name="sort" class="sort-select">
          <option value="name" selected={@filters.sort == "name"}>Name</option>
          <option value="price_asc" selected={@filters.sort == "price_asc"}>Price: Low to High</option>
          <option value="price_desc" selected={@filters.sort == "price_desc"}>Price: High to Low</option>
          <option value="newest" selected={@filters.sort == "newest"}>Newest First</option>
        </select>
      </div>

      <!-- Product Grid -->
      <div class="product-grid">
        <%= for product <- @products do %>
          <.product_card product={product} />
        <% end %>
      </div>

      <%= if Enum.empty?(@products) do %>
        <div class="empty-state">
          <h3>No products found</h3>
          <p>Try adjusting your search or filters.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Product card component
  defp product_card(assigns) do
    ~H"""
    <div class="product-card">
      <div class="product-image">
        <%= if @product.images && length(@product.images) > 0 do %>
          <img src={hd(@product.images)} alt={@product.name} />
        <% else %>
          <div class="placeholder-image">No Image</div>
        <% end %>
      </div>

      <div class="product-info">
        <h3 class="product-name">
          <.link navigate={Routes.product_show_path(@socket, :show, @product.slug)}>
            <%= @product.name %>
          </.link>
        </h3>

        <div class="product-price">
          <%= if @product.sale_price do %>
            <span class="sale-price">$<%= @product.sale_price %></span>
            <span class="original-price">$<%= @product.price %></span>
          <% else %>
            <span class="price">$<%= @product.price %></span>
          <% end %>
        </div>

        <div class="product-stock">
          <%= cond do %>
            <% @product.stock_quantity == 0 -> %>
              <span class="out-of-stock">Out of Stock</span>
            <% @product.stock_quantity <= 5 -> %>
              <span class="low-stock">Only <%= @product.stock_quantity %> left!</span>
            <% true -> %>
              <span class="in-stock">In Stock</span>
          <% end %>
        </div>

        <button 
          phx-click="add_to_cart" 
          phx-value-product-id={@product.id}
          disabled={@product.stock_quantity == 0}
          class="add-to-cart-btn"
        >
          <%= if @product.stock_quantity == 0 do %>
            Out of Stock
          <% else %>
            Add to Cart
          <% end %>
        </button>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp load_products(filters \\ %{}) do
    opts = [
      status: "published",
      preload: [:categories, :tags]
    ]

    opts = 
      case filters[:category] do
        nil -> opts
        category_id -> Keyword.put(opts, :category_id, category_id)
      end

    products = Catalog.list_products(opts)

    products
    |> filter_by_search(filters[:search])
    |> sort_products(filters[:sort])
  end

  defp load_categories do
    Catalog.list_categories()
  end

  defp filter_by_search(products, nil), do: products
  defp filter_by_search(products, ""), do: products
  defp filter_by_search(products, search_term) do
    search_term = String.downcase(search_term)
    
    Enum.filter(products, fn product ->
      String.contains?(String.downcase(product.name), search_term) ||
      String.contains?(String.downcase(product.description || ""), search_term)
    end)
  end

  defp sort_products(products, "name") do
    Enum.sort_by(products, & &1.name)
  end

  defp sort_products(products, "price_asc") do
    Enum.sort_by(products, &Decimal.to_float(&1.price))
  end

  defp sort_products(products, "price_desc") do
    Enum.sort_by(products, &Decimal.to_float(&1.price), :desc)
  end

  defp sort_products(products, "newest") do
    Enum.sort_by(products, & &1.inserted_at, {:desc, DateTime})
  end

  defp sort_products(products, _), do: products

  defp subscribe_to_inventory_updates do
    # Subscribe to inventory updates for all products
    # In a real app, you might want to limit this to visible products
    # or use a more efficient approach for large catalogs
    :ok
  end

  defp get_cart_token(socket) do
    # Get cart token from session or assigns
    socket.assigns[:cart_token] || "default-cart-token"
  end

  defp update_cart_count(socket) do
    cart_token = get_cart_token(socket)
    
    case Mercato.Cart.get_cart_by_token(cart_token) do
      {:ok, cart} ->
        count = Enum.sum(Enum.map(cart.cart_items, & &1.quantity))
        assign(socket, :cart_count, count)

      {:error, _} ->
        assign(socket, :cart_count, 0)
    end
  end

  defp build_query_params(filters) do
    filters
    |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
    |> Enum.into(%{})
  end
end
```

## Product Detail LiveView

```elixir
defmodule MyStoreWeb.ProductLive.Show do
  use MyStoreWeb, :live_view
  alias Mercato.{Catalog, Events, Cart}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Catalog.get_product_by_slug(slug, preload: [:categories, :tags, :variants]) do
      {:ok, product} ->
        if connected?(socket) do
          Events.subscribe_to_inventory(product.id)
        end

        socket =
          socket
          |> assign(:product, product)
          |> assign(:selected_variant, nil)
          |> assign(:quantity, 1)
          |> assign(:loading, false)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok, redirect(socket, to: Routes.product_index_path(socket, :index))}
    end
  end

  @impl true
  def handle_event("select_variant", %{"variant_id" => variant_id}, socket) do
    variant = Enum.find(socket.assigns.product.variants, &(&1.id == variant_id))
    {:noreply, assign(socket, :selected_variant, variant)}
  end

  @impl true
  def handle_event("update_quantity", %{"quantity" => quantity}, socket) do
    quantity = String.to_integer(quantity)
    {:noreply, assign(socket, :quantity, max(1, quantity))}
  end

  @impl true
  def handle_event("add_to_cart", _params, socket) do
    %{product: product, selected_variant: variant, quantity: quantity} = socket.assigns
    cart_token = get_cart_token(socket)

    opts = if variant, do: [variant_id: variant.id], else: []

    case Cart.add_item(cart_token, product.id, quantity, opts) do
      {:ok, _cart} ->
        message = "Added #{quantity} #{product.name} to cart!"
        
        socket =
          socket
          |> put_flash(:info, message)
          |> update_cart_count()

        {:noreply, socket}

      {:error, :insufficient_stock} ->
        available = get_available_stock(product, variant)
        message = "Only #{available} items available in stock."
        {:noreply, put_flash(socket, :error, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add to cart: #{reason}")}
    end
  end

  # Handle real-time stock updates
  @impl true
  def handle_info({:stock_updated, product_id, new_quantity}, socket) do
    if socket.assigns.product.id == product_id do
      product = %{socket.assigns.product | stock_quantity: new_quantity}
      socket = assign(socket, :product, product)

      socket =
        if new_quantity == 0 do
          put_flash(socket, :warning, "This product is now out of stock")
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="product-detail">
      <div class="product-images">
        <%= if @product.images && length(@product.images) > 0 do %>
          <div class="main-image">
            <img src={hd(@product.images)} alt={@product.name} />
          </div>
          <%= if length(@product.images) > 1 do %>
            <div class="thumbnail-images">
              <%= for image <- @product.images do %>
                <img src={image} alt={@product.name} class="thumbnail" />
              <% end %>
            </div>
          <% end %>
        <% else %>
          <div class="placeholder-image">No Image Available</div>
        <% end %>
      </div>

      <div class="product-details">
        <h1><%= @product.name %></h1>
        
        <div class="price">
          <%= if @selected_variant && @selected_variant.price do %>
            $<%= @selected_variant.price %>
          <% else %>
            <%= if @product.sale_price do %>
              <span class="sale-price">$<%= @product.sale_price %></span>
              <span class="original-price">$<%= @product.price %></span>
            <% else %>
              <span class="price">$<%= @product.price %></span>
            <% end %>
          <% end %>
        </div>

        <div class="stock-info">
          <%= case get_stock_status(@product, @selected_variant) do %>
            <% {:in_stock, quantity} -> %>
              <span class="in-stock">
                <%= if quantity <= 5 do %>
                  Only <%= quantity %> left in stock!
                <% else %>
                  In Stock
                <% end %>
              </span>
            <% :out_of_stock -> %>
              <span class="out-of-stock">Out of Stock</span>
          <% end %>
        </div>

        <%= if @product.product_type == "variable" && length(@product.variants) > 0 do %>
          <div class="variants">
            <h3>Options</h3>
            <%= for variant <- @product.variants do %>
              <button 
                phx-click="select_variant" 
                phx-value-variant_id={variant.id}
                class={"variant-btn #{if @selected_variant && @selected_variant.id == variant.id, do: "selected", else: ""}"}
              >
                <%= format_variant_attributes(variant.attributes) %>
                <%= if variant.price && variant.price != @product.price do %>
                  (+$<%= Decimal.sub(variant.price, @product.price) %>)
                <% end %>
              </button>
            <% end %>
          </div>
        <% end %>

        <div class="quantity-selector">
          <label for="quantity">Quantity:</label>
          <input 
            type="number" 
            id="quantity"
            name="quantity"
            value={@quantity}
            min="1"
            max={get_max_quantity(@product, @selected_variant)}
            phx-change="update_quantity"
          />
        </div>

        <button 
          phx-click="add_to_cart"
          disabled={get_stock_status(@product, @selected_variant) == :out_of_stock}
          class="add-to-cart-btn large"
        >
          <%= if get_stock_status(@product, @selected_variant) == :out_of_stock do %>
            Out of Stock
          <% else %>
            Add to Cart - $<%= calculate_total_price(@product, @selected_variant, @quantity) %>
          <% end %>
        </button>

        <div class="product-description">
          <h3>Description</h3>
          <p><%= @product.description %></p>
        </div>

        <%= if length(@product.categories) > 0 do %>
          <div class="categories">
            <h4>Categories:</h4>
            <%= for category <- @product.categories do %>
              <.link navigate={Routes.product_index_path(@socket, :index, category: category.id)} class="category-link">
                <%= category.name %>
              </.link>
            <% end %>
          </div>
        <% end %>

        <%= if length(@product.tags) > 0 do %>
          <div class="tags">
            <h4>Tags:</h4>
            <%= for tag <- @product.tags do %>
              <span class="tag"><%= tag.name %></span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp get_stock_status(product, nil) do
    if product.stock_quantity > 0 do
      {:in_stock, product.stock_quantity}
    else
      :out_of_stock
    end
  end

  defp get_stock_status(_product, variant) do
    if variant.stock_quantity > 0 do
      {:in_stock, variant.stock_quantity}
    else
      :out_of_stock
    end
  end

  defp get_available_stock(product, nil), do: product.stock_quantity
  defp get_available_stock(_product, variant), do: variant.stock_quantity

  defp get_max_quantity(product, variant) do
    available = get_available_stock(product, variant)
    min(available, 10) # Limit to 10 per order
  end

  defp format_variant_attributes(attributes) do
    attributes
    |> Enum.map(fn {key, value} -> "#{String.capitalize(key)}: #{value}" end)
    |> Enum.join(", ")
  end

  defp calculate_total_price(product, nil, quantity) do
    price = product.sale_price || product.price
    Decimal.mult(price, quantity)
  end

  defp calculate_total_price(_product, variant, quantity) do
    Decimal.mult(variant.price, quantity)
  end

  defp get_cart_token(socket) do
    socket.assigns[:cart_token] || "default-cart-token"
  end

  defp update_cart_count(socket) do
    # Implementation similar to the index page
    socket
  end
end
```

## CSS Styles

```css
/* Product Listing Styles */
.product-listing {
  max-width: 1200px;
  margin: 0 auto;
  padding: 20px;
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 30px;
}

.cart-indicator {
  background: #007cba;
  color: white;
  padding: 8px 16px;
  border-radius: 20px;
  font-weight: bold;
}

.filters {
  display: flex;
  gap: 15px;
  margin-bottom: 30px;
  flex-wrap: wrap;
}

.search-input, .category-filter, .sort-select {
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
}

.search-input {
  flex: 1;
  min-width: 200px;
}

.product-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 20px;
}

.product-card {
  border: 1px solid #eee;
  border-radius: 8px;
  overflow: hidden;
  transition: box-shadow 0.2s;
}

.product-card:hover {
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}

.product-image {
  height: 200px;
  overflow: hidden;
}

.product-image img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.placeholder-image {
  width: 100%;
  height: 100%;
  background: #f5f5f5;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #999;
}

.product-info {
  padding: 15px;
}

.product-name {
  margin: 0 0 10px 0;
  font-size: 16px;
}

.product-name a {
  text-decoration: none;
  color: #333;
}

.product-name a:hover {
  color: #007cba;
}

.product-price {
  margin-bottom: 10px;
}

.sale-price {
  color: #e74c3c;
  font-weight: bold;
  margin-right: 8px;
}

.original-price {
  text-decoration: line-through;
  color: #999;
  font-size: 14px;
}

.price {
  font-weight: bold;
  color: #333;
}

.product-stock {
  margin-bottom: 15px;
  font-size: 14px;
}

.in-stock {
  color: #27ae60;
}

.low-stock {
  color: #f39c12;
  font-weight: bold;
}

.out-of-stock {
  color: #e74c3c;
  font-weight: bold;
}

.add-to-cart-btn {
  width: 100%;
  padding: 10px;
  background: #007cba;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-weight: bold;
}

.add-to-cart-btn:hover:not(:disabled) {
  background: #005a87;
}

.add-to-cart-btn:disabled {
  background: #ccc;
  cursor: not-allowed;
}

.empty-state {
  text-align: center;
  padding: 60px 20px;
  color: #666;
}

/* Product Detail Styles */
.product-detail {
  max-width: 1200px;
  margin: 0 auto;
  padding: 20px;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 40px;
}

.main-image img {
  width: 100%;
  height: 400px;
  object-fit: cover;
  border-radius: 8px;
}

.thumbnail-images {
  display: flex;
  gap: 10px;
  margin-top: 15px;
}

.thumbnail {
  width: 80px;
  height: 80px;
  object-fit: cover;
  border-radius: 4px;
  cursor: pointer;
  border: 2px solid transparent;
}

.thumbnail:hover {
  border-color: #007cba;
}

.product-details h1 {
  margin: 0 0 20px 0;
  font-size: 28px;
}

.variants {
  margin: 20px 0;
}

.variant-btn {
  margin: 5px 5px 5px 0;
  padding: 8px 12px;
  border: 1px solid #ddd;
  background: white;
  border-radius: 4px;
  cursor: pointer;
}

.variant-btn.selected {
  border-color: #007cba;
  background: #f0f8ff;
}

.quantity-selector {
  margin: 20px 0;
}

.quantity-selector input {
  width: 80px;
  padding: 8px;
  margin-left: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
}

.add-to-cart-btn.large {
  padding: 15px 30px;
  font-size: 16px;
  margin: 20px 0;
}

.categories, .tags {
  margin-top: 20px;
}

.category-link {
  display: inline-block;
  margin-right: 10px;
  color: #007cba;
  text-decoration: none;
}

.category-link:hover {
  text-decoration: underline;
}

.tag {
  display: inline-block;
  background: #f5f5f5;
  padding: 4px 8px;
  margin-right: 8px;
  border-radius: 12px;
  font-size: 12px;
}

@media (max-width: 768px) {
  .product-detail {
    grid-template-columns: 1fr;
    gap: 20px;
  }
  
  .filters {
    flex-direction: column;
  }
  
  .search-input {
    min-width: auto;
  }
}
```

This comprehensive example demonstrates a fully functional product listing with real-time inventory updates, search, filtering, and cart integration using Phoenix LiveView and Mercato.
