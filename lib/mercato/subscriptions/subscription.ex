defmodule Mercato.Subscriptions.Subscription do
  @moduledoc """
  Schema for subscriptions.

  A subscription represents a recurring billing arrangement for a product or service.
  Subscriptions automatically generate orders at specified intervals based on the
  billing cycle configuration.

  ## Status Lifecycle

  - `active`: Subscription is active and will generate renewal orders
  - `paused`: Subscription is temporarily suspended, no renewals generated
  - `cancelled`: Subscription is permanently cancelled, no future renewals
  - `expired`: Subscription has reached its end date or failed renewal

  ## Billing Cycles

  - `daily`: Renews every day
  - `weekly`: Renews every week
  - `monthly`: Renews every month
  - `yearly`: Renews every year

  ## Fields

  - `user_id`: Reference to the customer who owns the subscription
  - `product_id`: Reference to the subscribed product
  - `variant_id`: Optional reference to specific product variant
  - `status`: Current subscription status
  - `billing_cycle`: How often the subscription renews
  - `trial_end_date`: Optional end date for trial period
  - `start_date`: When the subscription becomes active
  - `next_billing_date`: When the next renewal order should be generated
  - `end_date`: Optional end date for the subscription
  - `billing_amount`: Amount charged per billing cycle
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Subscriptions.SubscriptionCycle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_options ~w(active paused cancelled expired)
  @billing_cycle_options ~w(daily weekly monthly yearly)

  schema "subscriptions" do
    field :user_id, :binary_id
    field :product_id, :binary_id
    field :variant_id, :binary_id
    field :status, :string, default: "active"
    field :billing_cycle, :string
    field :trial_end_date, :date
    field :start_date, :date
    field :next_billing_date, :date
    field :end_date, :date
    field :billing_amount, :decimal

    has_many :cycles, SubscriptionCycle, foreign_key: :subscription_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new subscription.
  """
  def create_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :user_id,
      :product_id,
      :variant_id,
      :status,
      :billing_cycle,
      :trial_end_date,
      :start_date,
      :next_billing_date,
      :end_date,
      :billing_amount
    ])
    |> validate_required([
      :user_id,
      :product_id,
      :status,
      :billing_cycle,
      :start_date,
      :next_billing_date,
      :billing_amount
    ])
    |> validate_inclusion(:status, @status_options)
    |> validate_inclusion(:billing_cycle, @billing_cycle_options)
    |> validate_number(:billing_amount, greater_than: Decimal.new("0"))
    |> validate_dates()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:variant_id)
  end

  @doc """
  Changeset for updating subscription status.
  """
  def status_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:status, :next_billing_date])
    |> validate_required([:status])
    |> validate_inclusion(:status, @status_options)
    |> validate_status_transition()
  end

  @doc """
  Changeset for updating billing information.
  """
  def billing_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:next_billing_date, :billing_amount])
    |> validate_required([:next_billing_date, :billing_amount])
    |> validate_number(:billing_amount, greater_than: Decimal.new("0"))
  end

  @doc """
  Changeset for pausing a subscription.
  """
  def pause_changeset(subscription, _attrs \\ %{}) do
    subscription
    |> change(status: "paused")
    |> validate_inclusion(:status, @status_options)
  end

  @doc """
  Changeset for resuming a subscription.
  """
  def resume_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:next_billing_date])
    |> change(status: "active")
    |> validate_required([:next_billing_date])
    |> validate_inclusion(:status, @status_options)
  end

  @doc """
  Changeset for cancelling a subscription.
  """
  def cancel_changeset(subscription, _attrs \\ %{}) do
    subscription
    |> change(status: "cancelled")
    |> validate_inclusion(:status, @status_options)
  end

  # Private Functions

  defp validate_dates(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)
    trial_end_date = get_field(changeset, :trial_end_date)
    next_billing_date = get_field(changeset, :next_billing_date)

    changeset
    |> validate_trial_end_after_start(start_date, trial_end_date)
    |> validate_end_after_start(start_date, end_date)
    |> validate_next_billing_after_start(start_date, next_billing_date)
  end

  defp validate_trial_end_after_start(changeset, start_date, trial_end_date) do
    if start_date && trial_end_date && Date.compare(trial_end_date, start_date) == :lt do
      add_error(changeset, :trial_end_date, "must be after start date")
    else
      changeset
    end
  end

  defp validate_end_after_start(changeset, start_date, end_date) do
    if start_date && end_date && Date.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be after start date")
    else
      changeset
    end
  end

  defp validate_next_billing_after_start(changeset, start_date, next_billing_date) do
    if start_date && next_billing_date && Date.compare(next_billing_date, start_date) == :lt do
      add_error(changeset, :next_billing_date, "must be after start date")
    else
      changeset
    end
  end

  defp validate_status_transition(changeset) do
    old_status = changeset.data.status
    new_status = get_change(changeset, :status)

    if new_status && !valid_status_transition?(old_status, new_status) do
      add_error(changeset, :status, "invalid status transition from #{old_status} to #{new_status}")
    else
      changeset
    end
  end

  # Define valid status transitions
  defp valid_status_transition?("active", new_status) when new_status in ~w(paused cancelled expired), do: true
  defp valid_status_transition?("paused", new_status) when new_status in ~w(active cancelled expired), do: true
  defp valid_status_transition?("cancelled", _new_status), do: false
  defp valid_status_transition?("expired", _new_status), do: false
  defp valid_status_transition?(_, _), do: false
end
