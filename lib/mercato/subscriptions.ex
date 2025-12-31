defmodule Mercato.Subscriptions do
  @moduledoc """
  The Subscriptions context.

  This module provides the public API for managing subscriptions, including
  creating subscriptions, managing subscription lifecycle, and processing
  recurring billing cycles.

  ## Features

  - Subscription creation and management
  - Billing cycle support (daily, weekly, monthly, yearly)
  - Subscription status management (active, paused, cancelled, expired)
  - Automatic renewal processing
  - Trial period support
  - Integration with orders for billing

  ## Usage

      # Create a subscription
      {:ok, subscription} = Mercato.Subscriptions.create_subscription(%{
        user_id: user_id,
        product_id: product_id,
        billing_cycle: "monthly",
        start_date: Date.utc_today(),
        billing_amount: Decimal.new("29.99")
      })

      # Pause a subscription
      {:ok, subscription} = Mercato.Subscriptions.pause_subscription(subscription_id)

      # Resume a subscription
      {:ok, subscription} = Mercato.Subscriptions.resume_subscription(subscription_id)

      # Cancel a subscription
      {:ok, subscription} = Mercato.Subscriptions.cancel_subscription(subscription_id)

      # Process renewal for a subscription
      {:ok, order} = Mercato.Subscriptions.process_renewal(subscription_id)
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mercato.Repo
  alias Mercato.Subscriptions.{Subscription, SubscriptionCycle}
  alias Mercato.Orders
  alias Mercato.Events

  @doc """
  Gets a subscription by ID.

  Returns the subscription with preloaded cycles.

  ## Examples

      iex> get_subscription!(subscription_id)
      %Subscription{}

      iex> get_subscription!("non-existent")
      ** (Ecto.NoResultsError)
  """
  def get_subscription!(subscription_id) do
    Subscription
    |> Repo.get!(subscription_id)
    |> Repo.preload(:cycles)
  end

  @doc """
  Gets a subscription by ID, returning {:ok, subscription} or {:error, :not_found}.

  ## Examples

      iex> get_subscription(subscription_id)
      {:ok, %Subscription{}}

      iex> get_subscription("non-existent")
      {:error, :not_found}
  """
  def get_subscription(subscription_id) do
    case Repo.get(Subscription, subscription_id) do
      nil ->
        {:error, :not_found}

      subscription ->
        subscription = Repo.preload(subscription, :cycles)
        {:ok, subscription}
    end
  end

  @doc """
  Lists subscriptions with optional filtering.

  ## Options

  - `:user_id` - Filter by user ID
  - `:status` - Filter by subscription status
  - `:billing_cycle` - Filter by billing cycle
  - `:product_id` - Filter by product ID
  - `:limit` - Limit number of results (default: 50)
  - `:offset` - Offset for pagination (default: 0)
  - `:order_by` - Order by field (default: :inserted_at)
  - `:order_direction` - Order direction (default: :desc)

  ## Examples

      iex> list_subscriptions()
      [%Subscription{}, ...]

      iex> list_subscriptions(user_id: user_id, status: "active")
      [%Subscription{}, ...]

      iex> list_subscriptions(billing_cycle: "monthly", limit: 10)
      [%Subscription{}, ...]
  """
  def list_subscriptions(opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    status = Keyword.get(opts, :status)
    billing_cycle = Keyword.get(opts, :billing_cycle)
    product_id = Keyword.get(opts, :product_id)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by, :inserted_at)
    order_direction = Keyword.get(opts, :order_direction, :desc)

    query =
      from s in Subscription,
        order_by: [{^order_direction, field(s, ^order_by)}],
        limit: ^limit,
        offset: ^offset

    query =
      if user_id do
        from s in query, where: s.user_id == ^user_id
      else
        query
      end

    query =
      if status do
        from s in query, where: s.status == ^status
      else
        query
      end

    query =
      if billing_cycle do
        from s in query, where: s.billing_cycle == ^billing_cycle
      else
        query
      end

    query =
      if product_id do
        from s in query, where: s.product_id == ^product_id
      else
        query
      end

    Repo.all(query)
    |> Repo.preload(:cycles)
  end

  @doc """
  Creates a subscription.

  ## Required Attributes

  - `:user_id` - ID of the user who owns the subscription
  - `:product_id` - ID of the product being subscribed to
  - `:billing_cycle` - Billing frequency ("daily", "weekly", "monthly", "yearly")
  - `:start_date` - When the subscription becomes active
  - `:billing_amount` - Amount charged per billing cycle

  ## Optional Attributes

  - `:variant_id` - Specific product variant (if applicable)
  - `:trial_end_date` - End date for trial period
  - `:end_date` - Optional end date for the subscription
  - `:status` - Initial status (defaults to "active")

  ## Examples

      iex> create_subscription(%{
      ...>   user_id: user_id,
      ...>   product_id: product_id,
      ...>   billing_cycle: "monthly",
      ...>   start_date: Date.utc_today(),
      ...>   billing_amount: Decimal.new("29.99")
      ...> })
      {:ok, %Subscription{}}

      iex> create_subscription(%{invalid: "attrs"})
      {:error, %Ecto.Changeset{}}
  """
  def create_subscription(attrs) do
    # Calculate next billing date based on start date and billing cycle
    attrs_with_next_billing = calculate_next_billing_date(attrs)

    %Subscription{}
    |> Subscription.create_changeset(attrs_with_next_billing)
    |> Repo.insert()
    |> case do
      {:ok, subscription} ->
        # Broadcast subscription created event
        Events.broadcast_subscription_created(subscription)
        {:ok, subscription}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Pauses a subscription.

  This function sets the subscription status to "paused" and prevents
  future renewal orders from being generated until resumed.

  ## Examples

      iex> pause_subscription(subscription_id)
      {:ok, %Subscription{}}

      iex> pause_subscription("non-existent")
      {:error, :not_found}
  """
  def pause_subscription(subscription_id) do
    with {:ok, subscription} <- get_subscription(subscription_id) do
      if subscription.status == "active" do
        subscription
        |> Subscription.pause_changeset()
        |> Repo.update()
        |> case do
          {:ok, paused_subscription} ->
            Events.broadcast_subscription_paused(paused_subscription)
            {:ok, paused_subscription}

          {:error, changeset} ->
            {:error, changeset}
        end
      else
        {:error, :cannot_pause_subscription}
      end
    end
  end

  @doc """
  Resumes a paused subscription.

  This function sets the subscription status to "active" and recalculates
  the next billing date based on the current date and billing cycle.

  ## Examples

      iex> resume_subscription(subscription_id)
      {:ok, %Subscription{}}

      iex> resume_subscription("non-existent")
      {:error, :not_found}
  """
  def resume_subscription(subscription_id) do
    with {:ok, subscription} <- get_subscription(subscription_id) do
      if subscription.status == "paused" do
        # Calculate new next billing date from today
        next_billing_date = calculate_next_billing_from_date(Date.utc_today(), subscription.billing_cycle)

        subscription
        |> Subscription.resume_changeset(%{next_billing_date: next_billing_date})
        |> Repo.update()
        |> case do
          {:ok, resumed_subscription} ->
            Events.broadcast_subscription_resumed(resumed_subscription)
            {:ok, resumed_subscription}

          {:error, changeset} ->
            {:error, changeset}
        end
      else
        {:error, :cannot_resume_subscription}
      end
    end
  end

  @doc """
  Cancels a subscription.

  This function sets the subscription status to "cancelled" and prevents
  any future renewal orders from being generated.

  ## Examples

      iex> cancel_subscription(subscription_id)
      {:ok, %Subscription{}}

      iex> cancel_subscription("non-existent")
      {:error, :not_found}
  """
  def cancel_subscription(subscription_id) do
    with {:ok, subscription} <- get_subscription(subscription_id) do
      if subscription.status in ~w(active paused) do
        subscription
        |> Subscription.cancel_changeset()
        |> Repo.update()
        |> case do
          {:ok, cancelled_subscription} ->
            Events.broadcast_subscription_cancelled(cancelled_subscription)
            {:ok, cancelled_subscription}

          {:error, changeset} ->
            {:error, changeset}
        end
      else
        {:error, :cannot_cancel_subscription}
      end
    end
  end

  @doc """
  Processes a renewal for a subscription.

  This function creates a new order for the subscription billing amount
  and creates a subscription cycle record to track the billing.

  ## Examples

      iex> process_renewal(subscription_id)
      {:ok, %Order{}}

      iex> process_renewal("non-existent")
      {:error, :not_found}
  """
  def process_renewal(subscription_id) do
    Repo.transaction(fn ->
      with {:ok, subscription} <- get_subscription(subscription_id) do
        if subscription.status == "active" &&
           Date.compare(subscription.next_billing_date, Date.utc_today()) != :gt do

          # Get the next cycle number
          cycle_number = get_next_cycle_number(subscription)

          # Create subscription cycle record
          {:ok, cycle} = create_subscription_cycle(subscription, cycle_number)

          # Create order for the subscription
          case create_renewal_order(subscription, cycle) do
            {:ok, order} ->
              # Update cycle with order ID and mark as completed
              {:ok, _updated_cycle} = complete_subscription_cycle(cycle, order.id)

              # Update subscription's next billing date
              next_billing_date = calculate_next_billing_from_date(
                subscription.next_billing_date,
                subscription.billing_cycle
              )

              {:ok, _updated_subscription} = update_subscription_billing_date(subscription, next_billing_date)

              # Broadcast renewal processed event
              Events.broadcast_subscription_renewed(subscription, order)

              order

            {:error, reason} ->
              # Mark cycle as failed
              {:ok, _failed_cycle} = fail_subscription_cycle(cycle)
              Repo.rollback(reason)
          end
        else
          Repo.rollback(:subscription_not_due_for_renewal)
        end
      else
        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Gets subscriptions that are due for renewal.

  Returns subscriptions with status "active" and next_billing_date
  on or before the specified date (defaults to today).

  ## Examples

      iex> get_subscriptions_due_for_renewal()
      [%Subscription{}, ...]

      iex> get_subscriptions_due_for_renewal(Date.add(Date.utc_today(), 1))
      [%Subscription{}, ...]
  """
  def get_subscriptions_due_for_renewal(date \\ Date.utc_today()) do
    from(s in Subscription,
      where: s.status == "active" and s.next_billing_date <= ^date,
      order_by: [asc: s.next_billing_date]
    )
    |> Repo.all()
    |> Repo.preload(:cycles)
  end

  # Private Functions

  defp calculate_next_billing_date(attrs) do
    start_date = Map.get(attrs, :start_date) || Map.get(attrs, "start_date")
    billing_cycle = Map.get(attrs, :billing_cycle) || Map.get(attrs, "billing_cycle")
    trial_end_date = Map.get(attrs, :trial_end_date) || Map.get(attrs, "trial_end_date")

    # If there's a trial period, billing starts after trial ends
    billing_start_date = trial_end_date || start_date

    next_billing_date =
      if billing_start_date && billing_cycle do
        calculate_next_billing_from_date(billing_start_date, billing_cycle)
      else
        nil
      end

    if next_billing_date do
      Map.put(attrs, :next_billing_date, next_billing_date)
    else
      attrs
    end
  end

  defp calculate_next_billing_from_date(date, billing_cycle) do
    case billing_cycle do
      "daily" -> Date.add(date, 1)
      "weekly" -> Date.add(date, 7)
      "monthly" -> Date.add(date, 30) # Simplified - could use proper month calculation
      "yearly" -> Date.add(date, 365) # Simplified - could use proper year calculation
      _ -> date
    end
  end

  defp get_next_cycle_number(subscription) do
    case Repo.one(
      from c in SubscriptionCycle,
        where: c.subscription_id == ^subscription.id,
        select: max(c.cycle_number)
    ) do
      nil -> 1
      max_cycle -> max_cycle + 1
    end
  end

  defp create_subscription_cycle(subscription, cycle_number) do
    %SubscriptionCycle{}
    |> SubscriptionCycle.create_changeset(%{
      subscription_id: subscription.id,
      cycle_number: cycle_number,
      billing_date: subscription.next_billing_date,
      amount: subscription.billing_amount,
      status: "pending"
    })
    |> Repo.insert()
  end

  defp create_renewal_order(subscription, cycle) do
    # Create order attributes for the subscription renewal
    order_attrs = %{
      user_id: subscription.user_id,
      subtotal: subscription.billing_amount,
      discount_total: Decimal.new("0.00"),
      shipping_total: Decimal.new("0.00"),
      tax_total: Decimal.new("0.00"),
      grand_total: subscription.billing_amount,
      payment_method: "subscription_billing",
      customer_notes: "Subscription renewal - Cycle #{cycle.cycle_number}"
    }

    # Create the order (this would typically integrate with the Orders context)
    # For now, we'll create a basic order structure
    case Orders.create_order_from_subscription(subscription, order_attrs) do
      {:ok, order} -> {:ok, order}
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_subscription_cycle(cycle, order_id) do
    cycle
    |> SubscriptionCycle.complete_changeset(%{order_id: order_id})
    |> Repo.update()
  end

  defp fail_subscription_cycle(cycle) do
    cycle
    |> SubscriptionCycle.fail_changeset()
    |> Repo.update()
  end

  defp update_subscription_billing_date(subscription, next_billing_date) do
    subscription
    |> Subscription.billing_changeset(%{next_billing_date: next_billing_date})
    |> Repo.update()
  end
end
