defmodule Mercato.Referrals do
  @moduledoc """
  The Referrals context provides functions for managing referral codes, tracking clicks, and calculating commissions.

  This context handles all referral-related operations including:
  - Referral code generation and management
  - Click tracking and attribution
  - Commission calculation and management
  - Referral statistics and reporting

  ## Examples

      # Generate a referral code for a user
      {:ok, referral_code} = Referrals.generate_referral_code(user_id, %{
        commission_type: "percentage",
        commission_value: Decimal.new("5")
      })

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

  ## Referral Code Management

  @doc """
  Generates a unique referral code for a user.

  Creates a new referral code with the specified commission settings.
  The code is automatically generated as a unique alphanumeric string.

  ## Options

  - `:commission_type` - Required. Either "percentage" or "fixed"
  - `:commission_value` - Required. Commission amount or percentage
  - `:code` - Optional. Custom code (will be validated for uniqueness)

  ## Examples

      iex> generate_referral_code(user_id, %{commission_type: "percentage", commission_value: Decimal.new("5")})
      {:ok, %ReferralCode{}}

      iex> generate_referral_code(user_id, %{commission_type: "fixed", commission_value: Decimal.new("10"), code: "CUSTOM123"})
      {:ok, %ReferralCode{}}
  """
  def generate_referral_code(user_id, opts \\ %{}) do
    attrs =
      opts
      |> Map.put(:user_id, user_id)
      |> Map.put_new_lazy(:code, fn -> generate_unique_code() end)

    %ReferralCode{}
    |> ReferralCode.changeset(attrs)
    |> repo().insert()
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
    query = from rc in ReferralCode, where: rc.code == ^normalized_code and rc.status == "active"

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
    query = from rc in ReferralCode, where: rc.user_id == ^user_id

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
    query = from rc in ReferralCode

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

        # Increment click count
        referral_code
        |> Ecto.Changeset.change(clicks_count: referral_code.clicks_count + 1)
        |> repo().update!()

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
        commission_amount = calculate_commission(order, referral_code)

        # Create commission record
        {:ok, commission} =
          %Commission{}
          |> Commission.changeset(%{
            referral_code_id: referral_code.id,
            order_id: order.id,
            referee_id: order.user_id,
            amount: commission_amount
          })
          |> repo().insert()

        # Update referral code statistics
        new_total_commission = Decimal.add(referral_code.total_commission, commission_amount)

        referral_code
        |> Ecto.Changeset.change(
          conversions_count: referral_code.conversions_count + 1,
          total_commission: new_total_commission
        )
        |> repo().update!()

        commission
      end)
    else
      {:error, :not_found} -> {:error, :referral_code_not_found}
      {:error, :order_not_found} -> {:error, :order_not_found}
    end
  end

  @doc """
  Calculates the commission amount for an order based on referral code settings.

  ## Examples

      iex> calculate_commission(order, referral_code)
      Decimal.new("5.00")
  """
  def calculate_commission(%Order{} = order, %ReferralCode{} = referral_code) do
    case referral_code.commission_type do
      "percentage" ->
        percentage = Decimal.div(referral_code.commission_value, 100)
        Decimal.mult(order.grand_total, percentage)

      "fixed" ->
        referral_code.commission_value
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
    case get_referral_code_by_user(user_id, preload: [:referral_clicks, :commissions]) do
      {:ok, referral_code} ->
        commissions_by_status = Enum.group_by(referral_code.commissions, & &1.status)

        pending_commission =
          commissions_by_status
          |> Map.get("pending", [])
          |> Enum.reduce(Decimal.new("0"), fn comm, acc -> Decimal.add(acc, comm.amount) end)

        approved_commission =
          commissions_by_status
          |> Map.get("approved", [])
          |> Enum.reduce(Decimal.new("0"), fn comm, acc -> Decimal.add(acc, comm.amount) end)

        paid_commission =
          commissions_by_status
          |> Map.get("paid", [])
          |> Enum.reduce(Decimal.new("0"), fn comm, acc -> Decimal.add(acc, comm.amount) end)

        conversion_rate =
          if referral_code.clicks_count > 0 do
            Decimal.div(Decimal.new(referral_code.conversions_count), Decimal.new(referral_code.clicks_count))
            |> Decimal.mult(100)
            |> Decimal.round(2)
          else
            Decimal.new("0")
          end

        recent_clicks =
          referral_code.referral_clicks
          |> Enum.sort_by(& &1.clicked_at, {:desc, DateTime})
          |> Enum.take(10)

        recent_conversions =
          referral_code.commissions
          |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
          |> Enum.take(10)

        %{
          referral_code: referral_code.code,
          total_clicks: referral_code.clicks_count,
          total_conversions: referral_code.conversions_count,
          conversion_rate: conversion_rate,
          total_commission: referral_code.total_commission,
          pending_commission: pending_commission,
          approved_commission: approved_commission,
          paid_commission: paid_commission,
          recent_clicks: recent_clicks,
          recent_conversions: recent_conversions
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
    query = from c in Commission

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
  defp filter_commissions_by_status(query, status), do: from(c in query, where: c.status == ^status)

  defp filter_commissions_by_user(query, nil), do: query

  defp filter_commissions_by_user(query, user_id) do
    from c in query,
      join: rc in ReferralCode,
      on: c.referral_code_id == rc.id,
      where: rc.user_id == ^user_id
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
      _ -> generate_unique_code() # Retry if code already exists
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
