# Traditional Controller Example

This example demonstrates how to build a traditional Phoenix controller-based e-commerce application using Mercato, without LiveView.

## Product Controller

```elixir
defmodule MyStoreWeb.ProductController do
  use MyStoreWeb, :controller
  alias Mercato.Catalog

  def index(conn, params) do
    # Parse query parameters
    filters = %{
      category: params["category"],
      search: params["search"],
      sort: params["sort"] || "name",
      page: String.to_integer(params["page"] || "1"),
      per_page: 12
    }

    # Load products with pagination
    products = load_products(filters)
    categories = Catalog.list_categories()
    
    # Calculate pagination info
    total_products = count_products(filters)
    total_pages = ceil(total_products / filters.per_page)

    conn
    |> assign(:products, products)
    |> assign(:categories, categories)
    |> assign(:filters, filters)
    |> assign(:pagination, %{
      current_page: filters.page,
      total_pages: total_pages,
      total_products: total_products,
      per_page: filters.per_page
    })
    |> render("index.html")
  end

  def show(conn, %{"slug" => slug}) do
    case Catalog.get_product_by_slug(slug, preload: [:categories, :tags, :variants]) do
      {:ok, product} ->
        # Get related products
        related_products = get_related_products(product)
        
        conn
        |> assign(:product, product)
        |> assign(:related_products, related_products)
        |> render("show.html")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Product not found")
        |> redirect(to: Routes.product_path(conn, :index))
    end
  end

  def category(conn, %{"category_slug" => category_slug} = params) do
    case Catalog.get_category_by_slug(category_slug) do
      {:ok, category} ->
        filters = %{
          category_id: category.id,
          search: params["search"],
          sort: params["sort"] || "name",
          page: String.to_integer(params["page"] || "1"),
          per_page: 12
        }

        products = load_products(filters)
        total_products = count_products(filters)
        total_pages = ceil(total_products / filters.per_page)

        conn
        |> assign(:category, category)
        |> assign(:products, products)
        |> assign(:filters, filters)
        |> assign(:pagination, %{
          current_page: filters.page,
          total_pages: total_pages,
          total_products: total_products,
          per_page: filters.per_page
        })
        |> render("category.html")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Category not found")
        |> redirect(to: Routes.product_path(conn, :index))
    end
  end

  # Admin actions
  def new(conn, _params) do
    changeset = Catalog.change_product(%Catalog.Product{})
    categories = Catalog.list_categories()

    conn
    |> assign(:changeset, changeset)
    |> assign(:categories, categories)
    |> render("new.html")
  end

  def create(conn, %{"product" => product_params}) do
    case Catalog.create_product(product_params) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product created successfully")
        |> redirect(to: Routes.product_path(conn, :show, product.slug))

      {:error, changeset} ->
        categories = Catalog.list_categories()

        conn
        |> assign(:changeset, changeset)
        |> assign(:categories, categories)
        |> render("new.html")
    end
  end

  def edit(conn, %{"id" => id}) do
    product = Catalog.get_product!(id, preload: [:categories])
    changeset = Catalog.change_product(product)
    categories = Catalog.list_categories()

    conn
    |> assign(:product, product)
    |> assign(:changeset, changeset)
    |> assign(:categories, categories)
    |> render("edit.html")
  end

  def update(conn, %{"id" => id, "product" => product_params}) do
    product = Catalog.get_product!(id)

    case Catalog.update_product(product, product_params) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product updated successfully")
        |> redirect(to: Routes.product_path(conn, :show, product.slug))

      {:error, changeset} ->
        categories = Catalog.list_categories()

        conn
        |> assign(:product, product)
        |> assign(:changeset, changeset)
        |> assign(:categories, categories)
        |> render("edit.html")
    end
  end

  def delete(conn, %{"id" => id}) do
    product = Catalog.get_product!(id)
    {:ok, _product} = Catalog.delete_product(product)

    conn
    |> put_flash(:info, "Product deleted successfully")
    |> redirect(to: Routes.product_path(conn, :index))
  end

  # Private helper functions

  defp load_products(filters) do
    opts = [
      status: "published",
      preload: [:categories, :tags],
      limit: filters.per_page,
      offset: (filters.page - 1) * filters.per_page
    ]

    opts = 
      case filters.category_id do
        nil -> opts
        category_id -> Keyword.put(opts, :category_id, category_id)
      end

    products = Catalog.list_products(opts)

    products
    |> filter_by_search(filters.search)
    |> sort_products(filters.sort)
  end

  defp count_products(filters) do
    opts = [status: "published"]

    opts = 
      case filters.category_id do
        nil -> opts
        category_id -> Keyword.put(opts, :category_id, category_id)
      end

    products = Catalog.list_products(opts)

    products
    |> filter_by_search(filters.search)
    |> length()
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

  defp get_related_products(product) do
    # Get products from the same categories
    category_ids = Enum.map(product.categories, & &1.id)
    
    if Enum.empty?(category_ids) do
      []
    else
      Catalog.list_products(
        category_ids: category_ids,
        exclude_id: product.id,
        limit: 4,
        status: "published",
        preload: [:categories]
      )
    end
  end
end
```

## Cart Controller

```elixir
defmodule MyStoreWeb.CartController do
  use MyStoreWeb, :controller
  alias Mercato.{Cart, Catalog}

  def show(conn, _params) do
    cart_token = get_cart_token(conn)
    {:ok, cart} = Cart.get_cart(cart_token)

    conn
    |> assign(:cart, cart)
    |> render("show.html")
  end

  def add_item(conn, %{"product_id" => product_id} = params) do
    cart_token = get_cart_token(conn)
    quantity = String.to_integer(params["quantity"] || "1")
    variant_id = params["variant_id"]

    opts = if variant_id, do: [variant_id: variant_id], else: []

    case Cart.add_item(cart_token, product_id, quantity, opts) do
      {:ok, _cart} ->
        product = Catalog.get_product!(product_id)
        
        conn
        |> put_flash(:info, "#{product.name} added to cart!")
        |> redirect_back_or_to_cart()

      {:error, :insufficient_stock} ->
        conn
        |> put_flash(:error, "Sorry, there's not enough stock available.")
        |> redirect_back_or_to_product(product_id)

      {:error, :product_not_found} ->
        conn
        |> put_flash(:error, "Product not found.")
        |> redirect(to: Routes.product_path(conn, :index))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not add item to cart: #{reason}")
        |> redirect_back_or_to_product(product_id)
    end
  end

  def update_item(conn, %{"item_id" => item_id, "quantity" => quantity_str}) do
    cart_token = get_cart_token(conn)
    quantity = String.to_integer(quantity_str)

    case Cart.update_item_quantity(cart_token, item_id, quantity) do
      {:ok, _cart} ->
        conn
        |> put_flash(:info, "Cart updated successfully")
        |> redirect(to: Routes.cart_path(conn, :show))

      {:error, :insufficient_stock} ->
        conn
        |> put_flash(:error, "Not enough stock available")
        |> redirect(to: Routes.cart_path(conn, :show))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not update cart: #{reason}")
        |> redirect(to: Routes.cart_path(conn, :show))
    end
  end

  def remove_item(conn, %{"item_id" => item_id}) do
    cart_token = get_cart_token(conn)
    {:ok, _cart} = Cart.remove_item(cart_token, item_id)

    conn
    |> put_flash(:info, "Item removed from cart")
    |> redirect(to: Routes.cart_path(conn, :show))
  end

  def clear(conn, _params) do
    cart_token = get_cart_token(conn)
    {:ok, _cart} = Cart.clear_cart(cart_token)

    conn
    |> put_flash(:info, "Cart cleared")
    |> redirect(to: Routes.cart_path(conn, :show))
  end

  def apply_coupon(conn, %{"coupon_code" => coupon_code}) do
    cart_token = get_cart_token(conn)

    case Cart.apply_coupon(cart_token, coupon_code) do
      {:ok, _cart} ->
        conn
        |> put_flash(:info, "Coupon applied successfully!")
        |> redirect(to: Routes.cart_path(conn, :show))

      {:error, reason} ->
        error_message = format_coupon_error(reason)
        
        conn
        |> put_flash(:error, error_message)
        |> redirect(to: Routes.cart_path(conn, :show))
    end
  end

  def remove_coupon(conn, _params) do
    cart_token = get_cart_token(conn)
    {:ok, _cart} = Cart.remove_coupon(cart_token)

    conn
    |> put_flash(:info, "Coupon removed")
    |> redirect(to: Routes.cart_path(conn, :show))
  end

  # AJAX endpoints for dynamic cart updates
  def add_item_ajax(conn, params) do
    case add_item_logic(conn, params) do
      {:ok, cart} ->
        json(conn, %{
          success: true,
          message: "Item added to cart",
          cart_count: cart_item_count(cart),
          cart_total: to_string(cart.grand_total)
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, message: format_error(reason)})
    end
  end

  def get_cart_summary(conn, _params) do
    cart_token = get_cart_token(conn)
    {:ok, cart} = Cart.get_cart(cart_token)

    json(conn, %{
      item_count: cart_item_count(cart),
      total: to_string(cart.grand_total),
      items: render_cart_items(cart.cart_items)
    })
  end

  # Private helper functions

  defp get_cart_token(conn) do
    case get_session(conn, :cart_token) do
      nil ->
        token = generate_cart_token()
        put_session(conn, :cart_token, token)
        token

      token ->
        token
    end
  end

  defp generate_cart_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp redirect_back_or_to_cart(conn) do
    case get_req_header(conn, "referer") do
      [referer] when referer != "" ->
        redirect(conn, external: referer)

      _ ->
        redirect(conn, to: Routes.cart_path(conn, :show))
    end
  end

  defp redirect_back_or_to_product(conn, product_id) do
    case get_req_header(conn, "referer") do
      [referer] when referer != "" ->
        redirect(conn, external: referer)

      _ ->
        product = Catalog.get_product!(product_id)
        redirect(conn, to: Routes.product_path(conn, :show, product.slug))
    end
  end

  defp add_item_logic(conn, %{"product_id" => product_id} = params) do
    cart_token = get_cart_token(conn)
    quantity = String.to_integer(params["quantity"] || "1")
    variant_id = params["variant_id"]

    opts = if variant_id, do: [variant_id: variant_id], else: []
    Cart.add_item(cart_token, product_id, quantity, opts)
  end

  defp cart_item_count(cart) do
    Enum.sum(Enum.map(cart.cart_items, & &1.quantity))
  end

  defp render_cart_items(items) do
    Enum.map(items, fn item ->
      %{
        id: item.id,
        name: item.product.name,
        quantity: item.quantity,
        unit_price: to_string(item.unit_price),
        total_price: to_string(item.total_price),
        image: get_product_image(item.product)
      }
    end)
  end

  defp get_product_image(product) do
    case product.images do
      [image | _] -> image
      _ -> nil
    end
  end

  defp format_coupon_error(:coupon_not_found), do: "Coupon code not found"
  defp format_coupon_error(:coupon_expired), do: "This coupon has expired"
  defp format_coupon_error(:usage_limit_exceeded), do: "This coupon has reached its usage limit"
  defp format_coupon_error(:minimum_spend_not_met), do: "Minimum spend requirement not met"
  defp format_coupon_error(reason), do: "Coupon error: #{reason}"

  defp format_error(:insufficient_stock), do: "Not enough stock available"
  defp format_error(:product_not_found), do: "Product not found"
  defp format_error(reason), do: "Error: #{reason}"
end
```

## Checkout Controller

```elixir
defmodule MyStoreWeb.CheckoutController do
  use MyStoreWeb, :controller
  alias Mercato.{Cart, Orders, Customers}

  def show(conn, _params) do
    cart_token = get_cart_token(conn)
    {:ok, cart} = Cart.get_cart(cart_token)

    if Enum.empty?(cart.cart_items) do
      conn
      |> put_flash(:error, "Your cart is empty")
      |> redirect(to: Routes.cart_path(conn, :show))
    else
      # Initialize checkout form
      changeset = Orders.change_order(%Orders.Order{})
      
      # Get customer addresses if logged in
      addresses = get_customer_addresses(conn)

      conn
      |> assign(:cart, cart)
      |> assign(:changeset, changeset)
      |> assign(:addresses, addresses)
      |> render("show.html")
    end
  end

  def create_order(conn, %{"order" => order_params}) do
    cart_token = get_cart_token(conn)
    {:ok, cart} = Cart.get_cart(cart_token)

    if Enum.empty?(cart.cart_items) do
      conn
      |> put_flash(:error, "Your cart is empty")
      |> redirect(to: Routes.cart_path(conn, :show))
    else
      # Add user_id if logged in
      order_params = 
        case get_current_user(conn) do
          nil -> order_params
          user -> Map.put(order_params, "user_id", user.id)
        end

      case Orders.create_order_from_cart(cart_token, order_params) do
        {:ok, order} ->
          # Clear the cart
          Cart.clear_cart(cart_token)

          # Create customer record if needed
          maybe_create_customer(conn, order)

          conn
          |> put_flash(:info, "Order placed successfully!")
          |> redirect(to: Routes.order_path(conn, :show, order.id))

        {:error, changeset} ->
          addresses = get_customer_addresses(conn)

          conn
          |> assign(:cart, cart)
          |> assign(:changeset, changeset)
          |> assign(:addresses, addresses)
          |> render("show.html")
      end
    end
  end

  def guest_checkout(conn, %{"guest" => guest_params, "order" => order_params}) do
    cart_token = get_cart_token(conn)
    
    # Merge guest info with order params
    full_order_params = Map.merge(order_params, %{
      "customer_email" => guest_params["email"],
      "customer_first_name" => guest_params["first_name"],
      "customer_last_name" => guest_params["last_name"],
      "customer_phone" => guest_params["phone"]
    })

    case Orders.create_order_from_cart(cart_token, full_order_params) do
      {:ok, order} ->
        # Clear the cart
        Cart.clear_cart(cart_token)

        # Store guest info in session for future orders
        conn = put_session(conn, :guest_info, guest_params)

        conn
        |> put_flash(:info, "Order placed successfully!")
        |> redirect(to: Routes.order_path(conn, :show, order.id))

      {:error, changeset} ->
        {:ok, cart} = Cart.get_cart(cart_token)
        addresses = get_customer_addresses(conn)

        conn
        |> assign(:cart, cart)
        |> assign(:changeset, changeset)
        |> assign(:addresses, addresses)
        |> assign(:guest_params, guest_params)
        |> render("show.html")
    end
  end

  # AJAX endpoint for address validation
  def validate_address(conn, %{"address" => address_params}) do
    # Perform address validation (integrate with address validation service)
    case validate_address_with_service(address_params) do
      {:ok, validated_address} ->
        json(conn, %{
          valid: true,
          address: validated_address,
          suggestions: []
        })

      {:error, :invalid_address, suggestions} ->
        json(conn, %{
          valid: false,
          suggestions: suggestions
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{valid: false, error: reason})
    end
  end

  # AJAX endpoint for shipping calculation
  def calculate_shipping(conn, %{"address" => address_params}) do
    cart_token = get_cart_token(conn)
    {:ok, cart} = Cart.get_cart(cart_token)

    # Calculate shipping options
    shipping_options = calculate_shipping_options(cart, address_params)

    json(conn, %{
      shipping_options: shipping_options
    })
  end

  # AJAX endpoint for tax calculation
  def calculate_tax(conn, %{"address" => address_params}) do
    cart_token = get_cart_token(conn)
    {:ok, cart} = Cart.get_cart(cart_token)

    # Calculate tax
    tax_amount = calculate_tax_amount(cart, address_params)

    json(conn, %{
      tax_amount: to_string(tax_amount)
    })
  end

  # Private helper functions

  defp get_cart_token(conn) do
    get_session(conn, :cart_token)
  end

  defp get_current_user(conn) do
    conn.assigns[:current_user]
  end

  defp get_customer_addresses(conn) do
    case get_current_user(conn) do
      nil -> []
      user ->
        case Customers.get_customer(user.id) do
          {:ok, customer} -> Customers.list_addresses(customer.id)
          {:error, :not_found} -> []
        end
    end
  end

  defp maybe_create_customer(conn, order) do
    case get_current_user(conn) do
      nil -> :ok # Guest checkout
      user ->
        # Create customer record if it doesn't exist
        case Customers.get_customer(user.id) do
          {:ok, _customer} -> :ok
          {:error, :not_found} ->
            Customers.create_customer(%{
              user_id: user.id,
              email: user.email,
              first_name: order.billing_address["first_name"],
              last_name: order.billing_address["last_name"],
              phone: order.billing_address["phone"]
            })
        end
    end
  end

  defp validate_address_with_service(address_params) do
    # Integrate with address validation service (e.g., Google Maps, SmartyStreets)
    # This is a placeholder implementation
    {:ok, address_params}
  end

  defp calculate_shipping_options(cart, address_params) do
    # Calculate shipping options using configured shipping calculator
    # This is a placeholder implementation
    [
      %{
        id: "standard",
        name: "Standard Shipping",
        description: "5-7 business days",
        price: "9.99"
      },
      %{
        id: "expedited",
        name: "Expedited Shipping",
        description: "2-3 business days",
        price: "19.99"
      }
    ]
  end

  defp calculate_tax_amount(cart, address_params) do
    # Calculate tax using configured tax calculator
    # This is a placeholder implementation
    Decimal.mult(cart.subtotal, Decimal.new("0.08"))
  end
end
```

## Order Controller

```elixir
defmodule MyStoreWeb.OrderController do
  use MyStoreWeb, :controller
  alias Mercato.Orders

  def index(conn, params) do
    user = get_current_user(conn)
    
    if user do
      page = String.to_integer(params["page"] || "1")
      per_page = 10

      orders = Orders.list_orders(
        user_id: user.id,
        limit: per_page,
        offset: (page - 1) * per_page,
        preload: [:order_items]
      )

      total_orders = Orders.count_orders(user_id: user.id)
      total_pages = ceil(total_orders / per_page)

      conn
      |> assign(:orders, orders)
      |> assign(:pagination, %{
        current_page: page,
        total_pages: total_pages,
        total_orders: total_orders,
        per_page: per_page
      })
      |> render("index.html")
    else
      conn
      |> put_flash(:error, "Please log in to view your orders")
      |> redirect(to: Routes.user_session_path(conn, :new))
    end
  end

  def show(conn, %{"id" => id}) do
    case Orders.get_order(id, preload: [:order_items, :order_status_history]) do
      {:ok, order} ->
        if can_view_order?(conn, order) do
          conn
          |> assign(:order, order)
          |> render("show.html")
        else
          conn
          |> put_flash(:error, "Order not found")
          |> redirect(to: Routes.page_path(conn, :index))
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Order not found")
        |> redirect(to: Routes.page_path(conn, :index))
    end
  end

  def cancel(conn, %{"id" => id}) do
    case Orders.get_order(id) do
      {:ok, order} ->
        if can_cancel_order?(conn, order) do
          case Orders.cancel_order(id, "Customer request") do
            {:ok, _order} ->
              conn
              |> put_flash(:info, "Order cancelled successfully")
              |> redirect(to: Routes.order_path(conn, :show, id))

            {:error, reason} ->
              conn
              |> put_flash(:error, "Could not cancel order: #{reason}")
              |> redirect(to: Routes.order_path(conn, :show, id))
          end
        else
          conn
          |> put_flash(:error, "Cannot cancel this order")
          |> redirect(to: Routes.order_path(conn, :show, id))
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Order not found")
        |> redirect(to: Routes.page_path(conn, :index))
    end
  end

  # Admin actions
  def admin_index(conn, params) do
    page = String.to_integer(params["page"] || "1")
    per_page = 20
    status_filter = params["status"]

    filters = if status_filter, do: [status: status_filter], else: []

    orders = Orders.list_orders(
      filters ++ [
        limit: per_page,
        offset: (page - 1) * per_page,
        preload: [:order_items]
      ]
    )

    total_orders = Orders.count_orders(filters)
    total_pages = ceil(total_orders / per_page)

    conn
    |> assign(:orders, orders)
    |> assign(:status_filter, status_filter)
    |> assign(:pagination, %{
      current_page: page,
      total_pages: total_pages,
      total_orders: total_orders,
      per_page: per_page
    })
    |> render("admin_index.html")
  end

  def update_status(conn, %{"id" => id, "status" => new_status}) do
    case Orders.update_status(id, new_status) do
      {:ok, _order} ->
        conn
        |> put_flash(:info, "Order status updated successfully")
        |> redirect(to: Routes.order_path(conn, :show, id))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not update order status: #{reason}")
        |> redirect(to: Routes.order_path(conn, :show, id))
    end
  end

  def refund(conn, %{"id" => id} = params) do
    amount = params["amount"] && Decimal.new(params["amount"])
    reason = params["reason"] || "Admin refund"

    case Orders.refund_order(id, amount, reason) do
      {:ok, _order} ->
        conn
        |> put_flash(:info, "Refund processed successfully")
        |> redirect(to: Routes.order_path(conn, :show, id))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not process refund: #{reason}")
        |> redirect(to: Routes.order_path(conn, :show, id))
    end
  end

  # Private helper functions

  defp get_current_user(conn) do
    conn.assigns[:current_user]
  end

  defp can_view_order?(conn, order) do
    user = get_current_user(conn)
    is_admin?(conn) || (user && order.user_id == user.id)
  end

  defp can_cancel_order?(conn, order) do
    user = get_current_user(conn)
    
    # Users can cancel their own orders if they're in pending or processing status
    user_can_cancel = user && order.user_id == user.id && 
                     order.status in [:pending, :processing]
    
    # Admins can cancel any order
    is_admin?(conn) || user_can_cancel
  end

  defp is_admin?(conn) do
    user = get_current_user(conn)
    user && user.role == "admin"
  end
end
```

## View Templates

### Product Index Template (`templates/product/index.html.heex`)

```heex
<div class="product-listing">
  <div class="header">
    <h1>Products</h1>
    <div class="results-info">
      Showing <%= length(@products) %> of <%= @pagination.total_products %> products
    </div>
  </div>

  <!-- Search and Filters -->
  <div class="filters">
    <%= form_for @conn, Routes.product_path(@conn, :index), [method: :get, class: "filter-form"], fn f -> %>
      <div class="search-group">
        <%= text_input f, :search, 
              value: @filters.search, 
              placeholder: "Search products...",
              class: "search-input" %>
      </div>

      <div class="category-group">
        <%= select f, :category, 
              [{"All Categories", ""}] ++ Enum.map(@categories, &{&1.name, &1.id}),
              selected: @filters.category,
              class: "category-select" %>
      </div>

      <div class="sort-group">
        <%= select f, :sort,
              [
                {"Name", "name"},
                {"Price: Low to High", "price_asc"},
                {"Price: High to Low", "price_desc"},
                {"Newest First", "newest"}
              ],
              selected: @filters.sort,
              class: "sort-select" %>
      </div>

      <%= submit "Filter", class: "btn btn-primary" %>
    <% end %>
  </div>

  <!-- Product Grid -->
  <div class="product-grid">
    <%= for product <- @products do %>
      <div class="product-card">
        <div class="product-image">
          <%= if product.images && length(product.images) > 0 do %>
            <%= link to: Routes.product_path(@conn, :show, product.slug) do %>
              <img src={hd(product.images)} alt={product.name} />
            <% end %>
          <% else %>
            <div class="placeholder-image">No Image</div>
          <% end %>
        </div>

        <div class="product-info">
          <h3 class="product-name">
            <%= link product.name, to: Routes.product_path(@conn, :show, product.slug) %>
          </h3>

          <div class="product-price">
            <%= if product.sale_price do %>
              <span class="sale-price">$<%= product.sale_price %></span>
              <span class="original-price">$<%= product.price %></span>
            <% else %>
              <span class="price">$<%= product.price %></span>
            <% end %>
          </div>

          <div class="product-stock">
            <%= cond do %>
              <% product.stock_quantity == 0 -> %>
                <span class="out-of-stock">Out of Stock</span>
              <% product.stock_quantity <= 5 -> %>
                <span class="low-stock">Only <%= product.stock_quantity %> left!</span>
              <% true -> %>
                <span class="in-stock">In Stock</span>
            <% end %>
          </div>

          <%= form_for @conn, Routes.cart_path(@conn, :add_item), [class: "add-to-cart-form"], fn f -> %>
            <%= hidden_input f, :product_id, value: product.id %>
            <%= hidden_input f, :quantity, value: 1 %>
            <%= submit "Add to Cart", 
                  disabled: product.stock_quantity == 0,
                  class: "add-to-cart-btn" %>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>

  <%= if Enum.empty?(@products) do %>
    <div class="empty-state">
      <h3>No products found</h3>
      <p>Try adjusting your search or filters.</p>
    </div>
  <% end %>

  <!-- Pagination -->
  <%= if @pagination.total_pages > 1 do %>
    <div class="pagination">
      <%= if @pagination.current_page > 1 do %>
        <%= link "← Previous", 
              to: Routes.product_path(@conn, :index, 
                Map.merge(@filters, %{page: @pagination.current_page - 1})),
              class: "pagination-link" %>
      <% end %>

      <%= for page <- pagination_range(@pagination) do %>
        <%= if page == @pagination.current_page do %>
          <span class="pagination-current"><%= page %></span>
        <% else %>
          <%= link page, 
                to: Routes.product_path(@conn, :index, 
                  Map.merge(@filters, %{page: page})),
                class: "pagination-link" %>
        <% end %>
      <% end %>

      <%= if @pagination.current_page < @pagination.total_pages do %>
        <%= link "Next →", 
              to: Routes.product_path(@conn, :index, 
                Map.merge(@filters, %{page: @pagination.current_page + 1})),
              class: "pagination-link" %>
      <% end %>
    </div>
  <% end %>
</div>
```

### Cart Template (`templates/cart/show.html.heex`)

```heex
<div class="cart-page">
  <h1>Shopping Cart</h1>

  <%= if Enum.empty?(@cart.cart_items) do %>
    <div class="empty-cart">
      <h2>Your cart is empty</h2>
      <p>Looks like you haven't added any items to your cart yet.</p>
      <%= link "Continue Shopping", 
            to: Routes.product_path(@conn, :index),
            class: "btn btn-primary" %>
    </div>
  <% else %>
    <div class="cart-content">
      <div class="cart-items">
        <table class="cart-table">
          <thead>
            <tr>
              <th>Product</th>
              <th>Price</th>
              <th>Quantity</th>
              <th>Total</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= for item <- @cart.cart_items do %>
              <tr class="cart-item">
                <td class="product-info">
                  <div class="product-details">
                    <%= if item.product.images && length(item.product.images) > 0 do %>
                      <img src={hd(item.product.images)} alt={item.product.name} class="product-image" />
                    <% end %>
                    
                    <div>
                      <h4><%= item.product.name %></h4>
                      <%= if item.variant do %>
                        <div class="variant-info">
                          <%= format_variant_attributes(item.variant.attributes) %>
                        </div>
                      <% end %>
                      <div class="product-sku">SKU: <%= item.product.sku %></div>
                    </div>
                  </div>
                </td>
                
                <td class="price">$<%= item.unit_price %></td>
                
                <td class="quantity">
                  <%= form_for @conn, Routes.cart_path(@conn, :update_item, item.id), [method: :put], fn f -> %>
                    <%= number_input f, :quantity, 
                          value: item.quantity,
                          min: 1,
                          max: get_max_quantity(item),
                          class: "quantity-input" %>
                    <%= submit "Update", class: "btn btn-sm btn-outline" %>
                  <% end %>
                </td>
                
                <td class="total"><strong>$<%= item.total_price %></strong></td>
                
                <td class="actions">
                  <%= link "Remove", 
                        to: Routes.cart_path(@conn, :remove_item, item.id),
                        method: :delete,
                        data: [confirm: "Are you sure?"],
                        class: "btn btn-sm btn-danger" %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <div class="cart-actions">
          <%= link "Clear Cart", 
                to: Routes.cart_path(@conn, :clear),
                method: :delete,
                data: [confirm: "Are you sure you want to clear your cart?"],
                class: "btn btn-outline" %>
          
          <%= link "Continue Shopping", 
                to: Routes.product_path(@conn, :index),
                class: "btn btn-outline" %>
        </div>
      </div>

      <div class="cart-sidebar">
        <!-- Coupon Section -->
        <div class="coupon-section">
          <h3>Coupon Code</h3>
          
          <%= if @cart.applied_coupon do %>
            <div class="applied-coupon">
              <div class="coupon-info">
                <span class="coupon-code">✓ <%= @cart.applied_coupon.code %></span>
                <span class="coupon-description">
                  <%= format_coupon_description(@cart.applied_coupon) %>
                </span>
              </div>
              <%= link "Remove", 
                    to: Routes.cart_path(@conn, :remove_coupon),
                    method: :delete,
                    class: "btn btn-sm btn-outline" %>
            </div>
          <% else %>
            <%= form_for @conn, Routes.cart_path(@conn, :apply_coupon), [method: :post], fn f -> %>
              <div class="coupon-input-group">
                <%= text_input f, :coupon_code, 
                      placeholder: "Enter coupon code",
                      class: "coupon-input" %>
                <%= submit "Apply", class: "btn btn-primary" %>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Cart Totals -->
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

        <!-- Checkout Button -->
        <div class="checkout-section">
          <%= link "Proceed to Checkout", 
                to: Routes.checkout_path(@conn, :show),
                class: "btn btn-primary btn-large" %>
          
          <div class="security-badges">
            <div class="security-badge">🔒 Secure Checkout</div>
            <div class="security-badge">✓ SSL Encrypted</div>
          </div>
        </div>
      </div>
    </div>
  <% end %>
</div>
```

## JavaScript Enhancement

```javascript
// assets/js/cart.js

// Add to cart with AJAX
document.addEventListener('DOMContentLoaded', function() {
  // Add to cart forms
  const addToCartForms = document.querySelectorAll('.add-to-cart-form');
  
  addToCartForms.forEach(form => {
    form.addEventListener('submit', function(e) {
      e.preventDefault();
      
      const formData = new FormData(form);
      const button = form.querySelector('button[type="submit"]');
      const originalText = button.textContent;
      
      // Show loading state
      button.textContent = 'Adding...';
      button.disabled = true;
      
      fetch('/cart/add_item_ajax', {
        method: 'POST',
        body: formData,
        headers: {
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      .then(response => response.json())
      .then(data => {
        if (data.success) {
          // Update cart indicator
          updateCartIndicator(data.cart_count, data.cart_total);
          
          // Show success message
          showNotification(data.message, 'success');
          
          // Reset button
          button.textContent = 'Added!';
          setTimeout(() => {
            button.textContent = originalText;
            button.disabled = false;
          }, 2000);
        } else {
          showNotification(data.message, 'error');
          button.textContent = originalText;
          button.disabled = false;
        }
      })
      .catch(error => {
        console.error('Error:', error);
        showNotification('An error occurred', 'error');
        button.textContent = originalText;
        button.disabled = false;
      });
    });
  });
  
  // Quantity update with debouncing
  const quantityInputs = document.querySelectorAll('.quantity-input');
  
  quantityInputs.forEach(input => {
    let timeout;
    
    input.addEventListener('input', function() {
      clearTimeout(timeout);
      
      timeout = setTimeout(() => {
        const form = input.closest('form');
        if (form) {
          // Auto-submit form after 1 second of no changes
          form.submit();
        }
      }, 1000);
    });
  });
});

function updateCartIndicator(count, total) {
  const cartCount = document.querySelector('.cart-count');
  const cartTotal = document.querySelector('.cart-total');
  
  if (cartCount) cartCount.textContent = count;
  if (cartTotal) cartTotal.textContent = `$${total}`;
}

function showNotification(message, type) {
  // Create notification element
  const notification = document.createElement('div');
  notification.className = `notification notification-${type}`;
  notification.textContent = message;
  
  // Add to page
  document.body.appendChild(notification);
  
  // Show with animation
  setTimeout(() => notification.classList.add('show'), 100);
  
  // Remove after 3 seconds
  setTimeout(() => {
    notification.classList.remove('show');
    setTimeout(() => notification.remove(), 300);
  }, 3000);
}
```

This comprehensive example demonstrates how to build a traditional Phoenix controller-based e-commerce application using Mercato, with proper error handling, pagination, AJAX enhancements, and a complete user experience.