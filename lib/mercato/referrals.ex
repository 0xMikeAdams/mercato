defmodule Mercato.Referrals do
  @moduledoc """
  The Referrals context provides functions for managing referral codes, tracking clicks, and calculating commissions.

  This context handles all referral-related operations including:
  - Referral code generation and management
  - Click tracking and attribution
  - Commission calculation and management
  - Referral statistics and reporting

  ## Examples

      # Generate a referral code for a user (commission terms come from store config)
      {:ok, referral_code} = Referrals.generate_referral_code(user_id)

      # Track a click on a referral code
      {:ok, click} = Referrals.track_click("ABC123", %{
        ip_address: "192.168.1.1",
        user_agent: "Mozilla/5.0...",
        referrer_url: "https://example.com"
      })

      # Track a conversion and create commission
      {:ok, commission} = Referrals.track_conversion("ABC123", order_id)

      # Get referral statistics
      stats = Referrals.get_referral_stats(user_id)
  """

  import Ecto.Query, warn: false
  alias Mercato
  alias Mercato.Referrals.{ReferralCode, ReferralClick, Commission}
  alias Mercato.Orders.Order
  alias Mercato.Telemetry

  ## Referral Code Management

  @doc """
  Generates a unique referral code for a user.

  Commission terms are **not** taken from the caller — they are resolved from the
  store-operator-controlled `:referral_commission` configuration (defaulting to a
  5% percentage commission). This prevents a user from minting a referral code
  that pays themselves an arbitrary rate. Configure the policy with:

      config :mercato, referral_commission: %{type: "percentage", value: Decimal.new("5")}

  ## Options

  - `:code` - Optional. A custom code suggestion (validated for format/uniqueness).

  Any `:commission_type`/`:commission_value` passed in `opts` is ignored.

  ## Examples

      iex> generate_referral_code(user_id)
      {:ok, %ReferralCode{}}

      iex> generate_referral_code(user_id, %{code: "CUSTOM123"})
      {:ok, %ReferralCode{}}
  """
  def generate_referral_code(user_id, opts \\ %{}) do
    policy = commission_policy()

    attrs =
      %{
        user_id: user_id,
        commission_type: policy.type,
        commission_value: policy.value
      }
      |> maybe_put_custom_code(opts)
      |> Map.put_new_lazy(:code, fn -> generate_unique_code() end)

    %ReferralCode{}
    |> ReferralCode.public_changeset(attrs)
    |> repo().insert()
    |> case do
      {:ok, referral_code} = result ->
        Telemetry.execute([:referral, :code_generate, :stop], %{count: 1}, %{referral_code_id: referral_code.id, user_id: user_id})
        result

      error ->
        error
    end
  end

  @doc """
  Gets a referral code by its code string.

  Returns `{:ok, referral_code}` if found, `{:error, :not_found}` otherwise.

  ## Options

  - `:preload` - List of associations to preload

  ## Examples

      iex> get_referral_code("ABC123")
      {:ok, %ReferralCode{}}

      iex> get_referral_code("NONEXISTENT")
      {:error, :not_found}
  """
  def get_referral_code(code, opts \\ []) do
    normalized_code = String.upcase(code)
    query = from(rc in ReferralCode, where: rc.code == ^normalized_code and rc.status == "active")

    case query |> maybe_preload(opts[:preload]) |> repo().one() do
      nil -> {:error, :not_found}
      referral_code -> {:ok, referral_code}
    end
  end

  @doc """
  Gets a referral code by user ID.

  Returns `{:ok, referral_code}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_referral_code_by_user(user_id)
      {:ok, %ReferralCode{}}

      iex> get_referral_code_by_user("nonexistent-user")
      {:error, :not_found}
  """
  def get_referral_code_by_user(user_id, opts \\ []) do
    query = from(rc in ReferralCode, where: rc.user_id == ^user_id)

    case query |> maybe_preload(opts[:preload]) |> repo().one() do
      nil -> {:error, :not_found}
      referral_code -> {:ok, referral_code}
    end
  end

  @doc """
  Lists referral codes with optional filters.

  ## Options

  - `:user_id` - Filter by user ID
  - `:status` - Filter by status ("active", "inactive")
  - `:preload` - List of associations to preload

  ## Examples

      iex> list_referral_codes()
      [%ReferralCode{}, ...]

      iex> list_referral_codes(status: "active")
      [%ReferralCode{status: "active"}, ...]
  """
  def list_referral_codes(opts \\ []) do
    query = from(rc in ReferralCode)

    query
    |> filter_by_user_id(opts[:user_id])
    |> filter_by_status(opts[:status])
    |> maybe_preload(opts[:preload])
    |> order_by([rc], desc: rc.inserted_at)
    |> repo().all()
  end

  defp filter_by_user_id(query, nil), do: query
  defp filter_by_user_id(query, user_id), do: from(rc in query, where: rc.user_id == ^user_id)

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: from(rc in query, where: rc.status == ^status)

  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, preloads), do: from(rc in query, preload: ^preloads)

  # Resolves the store-operator-controlled commission policy. Commission terms are a
  # store-level setting, never something an end user supplies on the request that
  # generates their own referral code. Configure via:
  #
  #     config :mercato, referral_commission: %{type: "percentage", value: Decimal.new("5")}
  defp commission_policy do
    case Application.get_env(:mercato, :referral_commission) do
      %{type: type, value: value} when type in ["percentage", "fixed"] ->
        %{type: type, value: to_decimal(value)}

      _ ->
        %{type: "percentage", value: Decimal.new("5")}
    end
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)

  # A caller may suggest a custom code (atom or string key); everything else in opts —
  # including any commission_type/commission_value — is ignored on the public path.
  defp maybe_put_custom_code(attrs, opts) do
    case Map.get(opts, :code) || Map.get(opts, "code") do
      nil -> attrs
      code -> Map.put(attrs, :code, code)
    end
  end

  ## Click Tracking

  @doc """
  Tracks a click on a referral code.

  Records the click with metadata and increments the click count on the referral code.
  This function should be called when someone accesses a `/r/<code>` URL.

  ## Required Fields
  - `ip_address` - IP address of the visitor
  - `user_agent` - Browser user agent string (optional)
  - `referrer_url` - URL the visitor came from (optional)

  ## Examples

      iex> track_click("ABC123", %{ip_address: "192.168.1.1", user_agent: "Mozilla/5.0..."})
      {:ok, %ReferralClick{}}

      iex> track_click("NONEXISTENT", %{ip_address: "192.168.1.1"})
      {:error, :referral_code_not_found}
  """
  def track_click(code, metadata \\ %{}) do
    with {:ok, referral_code} <- get_referral_code(code) do
      repo().transaction(fn ->
        # Create click record
        {:ok, click} =
          %ReferralClick{}
          |> ReferralClick.changeset(
            metadata
            |> Map.put(:referral_code_id, referral_code.id)
            |> Map.put(:clicked_at, DateTime.utc_now())
          )
          |> repo().insert()

        {updated_count, _} =
          from(rc in ReferralCode, where: rc.id == ^referral_code.id)
          |> repo().update_all(inc: [clicks_count: 1])

        if updated_count != 1 do
          repo().rollback(:referral_code_not_found)
        end

        Telemetry.execute([:referral, :click, :stop], %{count: 1}, %{referral_code_id: referral_code.id})
        click
      end)
    else
      {:error, :not_found} -> {:error, :referral_code_not_found}
    end
  end

  ## Conversion Tracking and Commission Management

  @doc """
  Tracks a conversion and creates a commission record.

  This function should be called when an order is completed by a customer
  who was referred through a referral code. It creates a commission record
  and updates the referral code statistics.

  ## Examples

      iex> track_conversion("ABC123", order_id)
      {:ok, %Commission{}}

      iex> track_conversion("NONEXISTENT", order_id)
      {:error, :referral_code_not_found}
  """
  def track_conversion(code, order_id) do
    with {:ok, referral_code} <- get_referral_code(code),
         {:ok, order} <- get_order(order_id) do
      repo().transaction(fn ->
        case existing_commission(order.id) do
          %Commission{} = existing ->
            # Idempotent: this order's conversion was already credited. Re-crediting
            # here would inflate total_commission (the order status machine can legally
            # re-enter "completed"), so we no-op and return the existing commission.
            existing

          nil ->
            commission_amount = calculate_commission(order, referral_code)
            insert_commission(referral_code, order, commission_amount)
        end
      end)
    else
      {:error, :not_found} -> {:error, :referral_code_not_found}
      {:error, :order_not_found} -> {:error, :order_not_found}
    end
  end

  defp existing_commission(order_id) do
    repo().get_by(Commission, order_id: order_id)
  end

  defp insert_commission(referral_code, order, commission_amount) do
    changeset =
      Commission.changeset(%Commission{}, %{
        referral_code_id: referral_code.id,
        order_id: order.id,
        referee_id: order.user_id,
        amount: commission_amount
      })

    case repo().insert(changeset) do
      {:ok, commission} ->
        {updated_count, _} =
          from(rc in ReferralCode, where: rc.id == ^referral_code.id)
          |> repo().update_all(inc: [conversions_count: 1, total_commission: commission_amount])

        if updated_count != 1 do
          repo().rollback(:referral_code_not_found)
        end

        commission

      {:error, %Ecto.Changeset{errors: errors}} ->
        # Lost a concurrent race for the same order_id (unique constraint). Treat as
        # already-credited rather than raising, preserving idempotency.
        if Keyword.has_key?(errors, :referral_code_id) or Keyword.has_key?(errors, :order_id) do
          existing_commission(order.id) || repo().rollback(:commission_conflict)
        else
          repo().rollback(:invalid_commission)
        end
    end
  end

  @doc """
  Calculates the commission amount for an order based on referral code settings.

  The result is capped at the order's `grand_total`: a `fixed` commission can be
  configured higher than a small order's value, and an uncapped payout would produce
  a negative-margin sale. Percentage commissions are already bounded by their 0–100
  range, but the cap applies uniformly as defense in depth.

  ## Examples

      iex> calculate_commission(order, referral_code)
      Decimal.new("5.00")
  """
  def calculate_commission(%Order{} = order, %ReferralCode{} = referral_code) do
    raw =
      case referral_code.commission_type do
        "percentage" ->
          percentage = Decimal.div(referral_code.commission_value, 100)
          Decimal.mult(order.grand_total, percentage)

        "fixed" ->
          referral_code.commission_value
      end

    if Decimal.compare(raw, order.grand_total) == :gt do
      order.grand_total
    else
      raw
    end
  end

  ## Statistics and Reporting

  @doc """
  Gets referral statistics for a user.

  Returns a map with comprehensive referral statistics including clicks,
  conversions, commission earned, and recent activity.

  ## Examples

      iex> get_referral_stats(user_id)
      %{
        referral_code: "ABC123",
        total_clicks: 150,
        total_conversions: 12,
        conversion_rate: Decimal.new("8.0"),
        total_commission: Decimal.new("60.00"),
        pending_commission: Decimal.new("15.00"),
        approved_commission: Decimal.new("30.00"),
        paid_commission: Decimal.new("15.00"),
        recent_clicks: [...],
        recent_conversions: [...]
      }
  """
  def get_referral_stats(user_id) do
    # NOTE: does not preload the full clicks/commissions associations (which is
    # unbounded for a popular code). Sums are computed with a GROUP BY aggregate and
    # the "recent" lists are fetched with their own LIMIT-ed queries.
    case get_referral_code_by_user(user_id) do
      {:ok, referral_code} ->
        commission_sums = commission_sums_by_status(referral_code.id)

        conversion_rate =
          if referral_code.clicks_count > 0 do
            Decimal.div(
              Decimal.new(referral_code.conversions_count),
              Decimal.new(referral_code.clicks_count)
            )
            |> Decimal.mult(100)
            |> Decimal.round(2)
          else
            Decimal.new("0")
          end

        %{
          referral_code: referral_code.code,
          total_clicks: referral_code.clicks_count,
          total_conversions: referral_code.conversions_count,
          conversion_rate: conversion_rate,
          total_commission: referral_code.total_commission,
          pending_commission: Map.fetch!(commission_sums, "pending"),
          approved_commission: Map.fetch!(commission_sums, "approved"),
          paid_commission: Map.fetch!(commission_sums, "paid"),
          recent_clicks: recent_clicks(referral_code.id),
          recent_conversions: recent_conversions(referral_code.id)
        }

      {:error, :not_found} ->
        %{
          referral_code: nil,
          total_clicks: 0,
          total_conversions: 0,
          conversion_rate: Decimal.new("0"),
          total_commission: Decimal.new("0"),
          pending_commission: Decimal.new("0"),
          approved_commission: Decimal.new("0"),
          paid_commission: Decimal.new("0"),
          recent_clicks: [],
          recent_conversions: []
        }
    end
  end

  # Sum of commission amounts per status, computed in SQL. Returns a map with every
  # status key present (defaulting to 0) so callers can Map.fetch!/2 safely.
  defp commission_sums_by_status(referral_code_id) do
    sums =
      from(c in Commission,
        where: c.referral_code_id == ^referral_code_id,
        group_by: c.status,
        select: {c.status, sum(c.amount)}
      )
      |> repo().all()
      |> Map.new(fn {status, total} -> {status, total || Decimal.new("0")} end)

    Enum.reduce(~w(pending approved paid), %{}, fn status, acc ->
      Map.put(acc, status, Map.get(sums, status, Decimal.new("0")))
    end)
  end

  defp recent_clicks(referral_code_id) do
    from(rc in ReferralClick,
      where: rc.referral_code_id == ^referral_code_id,
      order_by: [desc: rc.clicked_at],
      limit: 10
    )
    |> repo().all()
  end

  defp recent_conversions(referral_code_id) do
    from(c in Commission,
      where: c.referral_code_id == ^referral_code_id,
      order_by: [desc: c.inserted_at],
      limit: 10
    )
    |> repo().all()
  end

  ## Commission Management

  @doc """
  Lists commissions with optional filters.

  ## Options

  - `:referral_code_id` - Filter by referral code ID
  - `:status` - Filter by status ("pending", "approved", "paid")
  - `:user_id` - Filter by referrer user ID
  - `:limit` - Limit number of results

  ## Examples

      iex> list_commissions()
      [%Commission{}, ...]

      iex> list_commissions(status: "pending")
      [%Commission{status: "pending"}, ...]
  """
  def list_commissions(opts \\ []) do
    query = from(c in Commission)

    query
    |> filter_commissions_by_referral_code(opts[:referral_code_id])
    |> filter_commissions_by_status(opts[:status])
    |> filter_commissions_by_user(opts[:user_id])
    |> maybe_limit_commissions(opts[:limit])
    |> order_by([c], desc: c.inserted_at)
    |> maybe_preload(opts[:preload])
    |> repo().all()
  end

  defp filter_commissions_by_referral_code(query, nil), do: query

  defp filter_commissions_by_referral_code(query, referral_code_id),
    do: from(c in query, where: c.referral_code_id == ^referral_code_id)

  defp filter_commissions_by_status(query, nil), do: query

  defp filter_commissions_by_status(query, status),
    do: from(c in query, where: c.status == ^status)

  defp filter_commissions_by_user(query, nil), do: query

  defp filter_commissions_by_user(query, user_id) do
    from(c in query,
      join: rc in ReferralCode,
      on: c.referral_code_id == rc.id,
      where: rc.user_id == ^user_id
    )
  end

  defp maybe_limit_commissions(query, nil), do: query
  defp maybe_limit_commissions(query, limit), do: from(c in query, limit: ^limit)

  @doc """
  Updates a commission status.

  ## Examples

      iex> update_commission_status(commission, "approved")
      {:ok, %Commission{}}

      iex> update_commission_status(commission, "paid")
      {:ok, %Commission{}}
  """
  def update_commission_status(%Commission{} = commission, new_status) do
    attrs = %{status: new_status}

    # Set paid_at timestamp when marking as paid
    attrs =
      if new_status == "paid" do
        Map.put(attrs, :paid_at, DateTime.utc_now())
      else
        attrs
      end

    commission
    |> Commission.changeset(attrs)
    |> repo().update()
  end

  ## Private Helper Functions

  # Generates a unique referral code
  defp generate_unique_code do
    code = generate_random_code()

    case repo().get_by(ReferralCode, code: code) do
      nil -> code
      # Retry if code already exists
      _ -> generate_unique_code()
    end
  end

  # Generates a random alphanumeric code
  defp generate_random_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(case: :upper, padding: false)
    |> String.slice(0, 6)
  end

  # Gets an order by ID
  defp get_order(order_id) do
    case repo().get(Order, order_id) do
      nil -> {:error, :order_not_found}
      order -> {:ok, order}
    end
  end

  defp repo, do: Mercato.repo()
end
