defmodule Mercato.Coupons do
  @moduledoc """
  The Coupons context provides functions for managing discount coupons and their usage.

  This context handles all coupon-related operations including:
  - Coupon CRUD operations
  - Coupon validation and application
  - Usage tracking and limit enforcement
  - Product and category eligibility rules

  ## Examples

      # Create a percentage discount coupon
      {:ok, coupon} = Coupons.create_coupon(%{
        code: "SAVE10",
        discount_type: "percentage",
        discount_value: Decimal.new("10"),
        valid_from: DateTime.utc_now(),
        valid_until: DateTime.add(DateTime.utc_now(), 30, :day)
      })

      # Validate a coupon against a cart
      case Coupons.validate_coupon("SAVE10", cart) do
        {:ok, coupon} -> # Coupon is valid
        {:error, reason} -> # Coupon is invalid
      end

      # Apply a coupon to calculate discount
      {:ok, discount_amount} = Coupons.apply_coupon(coupon, cart)
  """

  import Ecto.Query, warn: false
  alias Mercato
  alias Mercato.Coupons.{Coupon, CouponUsage}
  alias Mercato.Cart.Cart

  ## Coupon Management

  @doc """
  Returns a list of coupons with optional filters.

  ## Options

  - `:discount_type` - Filter by discount type
  - `:status` - Filter by status ("active", "expired", "inactive")
  - `:preload` - List of associations to preload

  ## Examples

      iex> list_coupons()
      [%Coupon{}, ...]

      iex> list_coupons(discount_type: "percentage")
      [%Coupon{discount_type: "percentage"}, ...]
  """
  def list_coupons(opts \\ []) do
    query = from(c in Coupon)

    query
    |> filter_by_discount_type(opts[:discount_type])
    |> filter_by_status(opts[:status])
    |> maybe_preload(opts[:preload])
    |> repo().all()
  end

  defp filter_by_discount_type(query, nil), do: query
  defp filter_by_discount_type(query, type), do: from(c in query, where: c.discount_type == ^type)

  defp filter_by_status(query, nil), do: query

  defp filter_by_status(query, "active") do
    now = DateTime.utc_now()

    from(c in query,
      where:
        c.valid_from <= ^now and
          (is_nil(c.valid_until) or c.valid_until >= ^now) and
          (is_nil(c.usage_limit) or c.usage_count < c.usage_limit)
    )
  end

  defp filter_by_status(query, "expired") do
    now = DateTime.utc_now()

    from(c in query,
      where: not is_nil(c.valid_until) and c.valid_until < ^now
    )
  end

  defp filter_by_status(query, "inactive") do
    now = DateTime.utc_now()

    from(c in query,
      where:
        c.valid_from > ^now or
          (not is_nil(c.usage_limit) and c.usage_count >= c.usage_limit)
    )
  end

  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, preloads), do: from(c in query, preload: ^preloads)

  @doc """
  Gets a single coupon by ID.

  Raises `Ecto.NoResultsError` if the coupon does not exist.

  ## Options

  - `:preload` - List of associations to preload

  ## Examples

      iex> get_coupon!("123e4567-e89b-12d3-a456-426614174000")
      %Coupon{}

      iex> get_coupon!("invalid-id")
      ** (Ecto.NoResultsError)
  """
  def get_coupon!(id, opts \\ []) do
    query = from(c in Coupon, where: c.id == ^id)

    query
    |> maybe_preload(opts[:preload])
    |> repo().one!()
  end

  @doc """
  Gets a single coupon by ID.

  Returns `{:ok, coupon}` if found, `{:error, :not_found}` otherwise.

  ## Options

  - `:preload` - List of associations to preload
  """
  def get_coupon(id, opts \\ []) do
    query = from(c in Coupon, where: c.id == ^id)

    case query |> maybe_preload(opts[:preload]) |> repo().one() do
      nil -> {:error, :not_found}
      coupon -> {:ok, coupon}
    end
  end

  @doc """
  Gets a single coupon by code.

  Returns `{:ok, coupon}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_coupon_by_code("SAVE10")
      {:ok, %Coupon{}}

      iex> get_coupon_by_code("NONEXISTENT")
      {:error, :not_found}
  """
  def get_coupon_by_code(code, opts \\ []) do
    normalized_code = String.upcase(code)
    query = from(c in Coupon, where: c.code == ^normalized_code)

    case query |> maybe_preload(opts[:preload]) |> repo().one() do
      nil -> {:error, :not_found}
      coupon -> {:ok, coupon}
    end
  end

  @doc """
  Creates a coupon.

  ## Examples

      iex> create_coupon(%{code: "SAVE10", discount_type: "percentage", discount_value: Decimal.new("10"), valid_from: DateTime.utc_now()})
      {:ok, %Coupon{}}

      iex> create_coupon(%{code: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_coupon(attrs \\ %{}) do
    %Coupon{}
    |> Coupon.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Updates a coupon.

  ## Examples

      iex> update_coupon(coupon, %{discount_value: Decimal.new("15")})
      {:ok, %Coupon{}}

      iex> update_coupon(coupon, %{discount_value: -10})
      {:error, %Ecto.Changeset{}}
  """
  def update_coupon(%Coupon{} = coupon, attrs) do
    coupon
    |> Coupon.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a coupon.

  ## Examples

      iex> delete_coupon(coupon)
      {:ok, %Coupon{}}

      iex> delete_coupon(coupon)
      {:error, %Ecto.Changeset{}}
  """
  def delete_coupon(%Coupon{} = coupon) do
    repo().delete(coupon)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking coupon changes.

  ## Examples

      iex> change_coupon(coupon)
      %Ecto.Changeset{data: %Coupon{}}
  """
  def change_coupon(%Coupon{} = coupon, attrs \\ %{}) do
    Coupon.changeset(coupon, attrs)
  end

  ## Coupon Validation and Application

  @doc """
  Validates a coupon against a cart.

  Checks all validation rules including:
  - Coupon exists and is active
  - Temporal validity (not expired)
  - Usage limits (global and per customer)
  - Minimum spend requirements
  - Product/category eligibility rules

  Returns `{:ok, coupon}` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> validate_coupon("SAVE10", cart)
      {:ok, %Coupon{}}

      iex> validate_coupon("EXPIRED", cart)
      {:error, :expired}

      iex> validate_coupon("NONEXISTENT", cart)
      {:error, :not_found}
  """
  def validate_coupon(code, %Cart{} = cart) do
    with {:ok, coupon} <- get_coupon_by_code(code),
         :ok <- validate_temporal_validity(coupon),
         :ok <- validate_usage_limits(coupon, cart.user_id),
         :ok <- validate_minimum_spend(coupon, cart),
         :ok <- validate_product_eligibility(coupon, cart) do
      {:ok, coupon}
    end
  end

  # Validates that the coupon is within its valid date range
  defp validate_temporal_validity(%Coupon{} = coupon) do
    now = DateTime.utc_now()

    cond do
      DateTime.compare(now, coupon.valid_from) == :lt ->
        {:error, :not_yet_active}

      coupon.valid_until && DateTime.compare(now, coupon.valid_until) == :gt ->
        {:error, :expired}

      true ->
        :ok
    end
  end

  # Validates that the coupon hasn't exceeded its usage limits
  defp validate_usage_limits(%Coupon{} = coupon, user_id) do
    cond do
      coupon.usage_limit && coupon.usage_count >= coupon.usage_limit ->
        {:error, :usage_limit_exceeded}

      coupon.usage_limit_per_customer && user_id ->
        customer_usage_count = get_customer_usage_count(coupon.id, user_id)

        if customer_usage_count >= coupon.usage_limit_per_customer do
          {:error, :customer_usage_limit_exceeded}
        else
          :ok
        end

      true ->
        :ok
    end
  end

  # Validates that the cart meets the minimum spend requirement
  defp validate_minimum_spend(%Coupon{} = coupon, %Cart{} = cart) do
    if coupon.min_spend && Decimal.compare(cart.subtotal, coupon.min_spend) == :lt do
      {:error, :minimum_spend_not_met}
    else
      :ok
    end
  end

  # Validates that the cart contains eligible products
  defp validate_product_eligibility(%Coupon{} = coupon, %Cart{} = cart) do
    # If no product/category rules are defined, all products are eligible.
    if has_product_rules?(coupon) do
      cart = preload_eligibility(coupon, cart)
      eligible_items = get_eligible_cart_items(coupon, cart.items)

      if Enum.empty?(eligible_items) do
        {:error, :no_eligible_products}
      else
        :ok
      end
    else
      :ok
    end
  end

  # Gets the number of times a customer has used a specific coupon
  defp get_customer_usage_count(coupon_id, user_id) do
    from(cu in CouponUsage,
      where: cu.coupon_id == ^coupon_id and cu.user_id == ^user_id,
      select: count(cu.id)
    )
    |> repo().one()
  end

  # Filters cart items to only those eligible for the coupon discount
  defp get_eligible_cart_items(%Coupon{} = coupon, cart_items) do
    Enum.filter(cart_items, fn item ->
      product = item.product
      category_ids = Enum.map(product.categories, & &1.id)

      # Check inclusion rules
      included_by_product =
        Enum.empty?(coupon.included_product_ids) ||
          product.id in coupon.included_product_ids

      included_by_category =
        Enum.empty?(coupon.included_category_ids) ||
          Enum.any?(category_ids, &(&1 in coupon.included_category_ids))

      # Check exclusion rules
      excluded_by_product = product.id in coupon.excluded_product_ids

      excluded_by_category =
        Enum.any?(category_ids, &(&1 in coupon.excluded_category_ids))

      # Item is eligible if it's included and not excluded
      (included_by_product || included_by_category) &&
        !excluded_by_product && !excluded_by_category
    end)
  end

  @doc """
  Applies a coupon to a cart and calculates the discount amount.

  This function assumes the coupon has already been validated against the cart.
  Use `validate_coupon/2` first to ensure the coupon is valid.

  Returns `{:ok, discount_amount}` with the calculated discount.

  ## Examples

      iex> apply_coupon(coupon, cart)
      {:ok, Decimal.new("5.00")}
  """
  def apply_coupon(%Coupon{} = coupon, %Cart{} = cart) do
    # Preload the product/category associations the eligibility checks need exactly once
    # here (only when the coupon actually needs them), so the discount helpers below don't
    # each re-preload the same cart on every recalculation.
    cart = preload_eligibility(coupon, cart)
    discount_amount = calculate_discount_amount(coupon, cart)
    {:ok, discount_amount}
  end

  # Calculates the discount amount based on coupon type and cart contents
  defp calculate_discount_amount(%Coupon{discount_type: "percentage"} = coupon, %Cart{} = cart) do
    eligible_amount = get_eligible_cart_amount(coupon, cart)
    discount = Decimal.mult(eligible_amount, Decimal.div(coupon.discount_value, 100))

    # Apply max_discount limit if specified
    if coupon.max_discount && Decimal.compare(discount, coupon.max_discount) == :gt do
      coupon.max_discount
    else
      discount
    end
  end

  defp calculate_discount_amount(%Coupon{discount_type: "fixed_cart"} = coupon, %Cart{} = cart) do
    eligible_amount = get_eligible_cart_amount(coupon, cart)

    # Don't discount more than the eligible amount
    if Decimal.compare(coupon.discount_value, eligible_amount) == :gt do
      eligible_amount
    else
      coupon.discount_value
    end
  end

  defp calculate_discount_amount(%Coupon{discount_type: "fixed_product"} = coupon, %Cart{} = cart) do
    # Eligibility associations are preloaded once in apply_coupon/2 (fixed_product always
    # needs them), so no preload here.
    eligible_items = get_eligible_cart_items(coupon, cart.items)

    eligible_items
    |> Enum.reduce(Decimal.new("0"), fn item, acc ->
      item_discount =
        if Decimal.compare(coupon.discount_value, item.unit_price) == :gt do
          item.unit_price
        else
          coupon.discount_value
        end

      total_item_discount = Decimal.mult(item_discount, item.quantity)
      Decimal.add(acc, total_item_discount)
    end)
  end

  defp calculate_discount_amount(%Coupon{discount_type: "free_shipping"}, %Cart{} = cart) do
    cart.shipping_total
  end

  # Gets the total amount of eligible cart items for discount calculation
  defp get_eligible_cart_amount(%Coupon{} = coupon, %Cart{} = cart) do
    # If no product/category rules, the entire subtotal is eligible. When rules exist the
    # eligibility associations were already preloaded by apply_coupon/2.
    if has_product_rules?(coupon) do
      eligible_items = get_eligible_cart_items(coupon, cart.items)

      eligible_items
      |> Enum.reduce(Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.total_price)
      end)
    else
      cart.subtotal
    end
  end

  # True when the coupon restricts eligibility by product or category.
  defp has_product_rules?(%Coupon{} = coupon) do
    not (Enum.empty?(coupon.included_product_ids) and
           Enum.empty?(coupon.excluded_product_ids) and
           Enum.empty?(coupon.included_category_ids) and
           Enum.empty?(coupon.excluded_category_ids))
  end

  # fixed_product discounts inspect every item's product/categories, so they always need
  # the eligibility associations; other types only need them when rules are present.
  defp needs_eligibility?(%Coupon{discount_type: "fixed_product"}), do: true
  defp needs_eligibility?(%Coupon{} = coupon), do: has_product_rules?(coupon)

  # Preloads product/categories once, only when the coupon needs them. Idempotent: a
  # no-op when the association is already loaded.
  defp preload_eligibility(%Coupon{} = coupon, %Cart{} = cart) do
    if needs_eligibility?(coupon) do
      repo().preload(cart, items: [product: :categories])
    else
      cart
    end
  end

  ## Coupon Usage Tracking

  @doc """
  Records the usage of a coupon for an order.

  This function should be called when an order is completed with a coupon applied.
  It creates a usage record and increments the coupon's usage count.

  Returns `{:ok, coupon_usage}` if successful.

  ## Examples

      iex> record_coupon_usage(coupon, order_id, user_id)
      {:ok, %CouponUsage{}}
  """
  def record_coupon_usage(%Coupon{} = coupon, order_id, user_id \\ nil) do
    repo().transaction(fn ->
      # Lock the coupon row for the life of the transaction. This serializes all usage
      # recording for this coupon, so the global AND per-customer caps are checked and
      # committed atomically — concurrent orders cannot race past either limit (the prior
      # version only made the global cap atomic; the per-customer cap stayed advisory).
      case repo().one(from(c in Coupon, where: c.id == ^coupon.id, lock: "FOR UPDATE")) do
        nil ->
          repo().rollback(:coupon_not_found)

        locked ->
          with :ok <- check_global_limit(locked),
               :ok <- check_customer_limit(locked, user_id),
               {:ok, usage} <- insert_coupon_usage(locked.id, order_id, user_id) do
            from(c in Coupon, where: c.id == ^locked.id)
            |> repo().update_all(inc: [usage_count: 1])

            usage
          else
            {:error, reason} -> repo().rollback(reason)
          end
      end
    end)
  end

  defp check_global_limit(%Coupon{usage_limit: nil}), do: :ok

  defp check_global_limit(%Coupon{usage_limit: limit, usage_count: count}) when count >= limit,
    do: {:error, :usage_limit_exceeded}

  defp check_global_limit(_coupon), do: :ok

  defp check_customer_limit(%Coupon{usage_limit_per_customer: nil}, _user_id), do: :ok
  defp check_customer_limit(_coupon, nil), do: :ok

  defp check_customer_limit(%Coupon{} = coupon, user_id) do
    if get_customer_usage_count(coupon.id, user_id) >= coupon.usage_limit_per_customer do
      {:error, :customer_usage_limit_exceeded}
    else
      :ok
    end
  end

  defp insert_coupon_usage(coupon_id, order_id, user_id) do
    %CouponUsage{}
    |> CouponUsage.changeset(%{
      coupon_id: coupon_id,
      user_id: user_id,
      order_id: order_id,
      used_at: DateTime.utc_now()
    })
    |> repo().insert()
  end

  @doc """
  Gets usage statistics for a coupon.

  Returns a map with usage statistics including total uses, unique customers, etc.

  ## Examples

      iex> get_coupon_usage_stats(coupon)
      %{
        total_uses: 25,
        unique_customers: 20,
        recent_uses: [%CouponUsage{}, ...]
      }
  """
  def get_coupon_usage_stats(%Coupon{} = coupon) do
    # Counts are computed in SQL rather than by loading every usage row into memory.
    # unique_customers counts distinct non-null user_ids (anonymous uses are excluded).
    totals =
      from(cu in CouponUsage,
        where: cu.coupon_id == ^coupon.id,
        select: %{
          total_uses: count(cu.id),
          unique_customers: count(cu.user_id, :distinct)
        }
      )
      |> repo().one()

    recent_uses =
      from(cu in CouponUsage,
        where: cu.coupon_id == ^coupon.id,
        order_by: [desc: cu.used_at],
        limit: 10
      )
      |> repo().all()

    %{
      total_uses: totals.total_uses,
      unique_customers: totals.unique_customers,
      recent_uses: recent_uses
    }
  end

  @doc """
  Lists coupon usages with optional filters.

  ## Options

  - `:coupon_id` - Filter by coupon ID
  - `:user_id` - Filter by user ID
  - `:order_id` - Filter by order ID
  - `:limit` - Limit number of results

  ## Examples

      iex> list_coupon_usages(coupon_id: coupon.id)
      [%CouponUsage{}, ...]
  """
  def list_coupon_usages(opts \\ []) do
    query = from(cu in CouponUsage)

    query
    |> filter_usages_by_coupon(opts[:coupon_id])
    |> filter_usages_by_user(opts[:user_id])
    |> filter_usages_by_order(opts[:order_id])
    |> maybe_limit(opts[:limit])
    |> order_by([cu], desc: cu.used_at)
    |> repo().all()
  end

  defp filter_usages_by_coupon(query, nil), do: query

  defp filter_usages_by_coupon(query, coupon_id),
    do: from(cu in query, where: cu.coupon_id == ^coupon_id)

  defp filter_usages_by_user(query, nil), do: query
  defp filter_usages_by_user(query, user_id), do: from(cu in query, where: cu.user_id == ^user_id)

  defp filter_usages_by_order(query, nil), do: query

  defp filter_usages_by_order(query, order_id),
    do: from(cu in query, where: cu.order_id == ^order_id)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: from(cu in query, limit: ^limit)

  defp repo, do: Mercato.repo()
end
