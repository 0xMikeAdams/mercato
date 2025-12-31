defmodule Mercato.Subscriptions.SubscriptionCycle do
  @moduledoc """
  Schema for subscription cycles.

  A subscription cycle represents a single billing period for a subscription.
  Each cycle tracks when billing occurred, the amount charged, and the resulting
  order if the billing was successful.

  ## Status Options

  - `pending`: Cycle is scheduled but not yet processed
  - `completed`: Cycle was successfully processed and order created
  - `failed`: Cycle processing failed (payment declined, etc.)

  ## Fields

  - `subscription_id`: Reference to the parent subscription
  - `cycle_number`: Sequential number of this cycle (1, 2, 3, etc.)
  - `billing_date`: Date when this cycle should be/was billed
  - `amount`: Amount charged for this cycle
  - `order_id`: Reference to the order created for this cycle (if successful)
  - `status`: Current status of this cycle
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_options ~w(pending completed failed)

  schema "subscription_cycles" do
    field :cycle_number, :integer
    field :billing_date, :date
    field :amount, :decimal
    field :order_id, :binary_id
    field :status, :string, default: "pending"

    belongs_to :subscription, Mercato.Subscriptions.Subscription

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new subscription cycle.
  """
  def create_changeset(cycle, attrs) do
    cycle
    |> cast(attrs, [
      :subscription_id,
      :cycle_number,
      :billing_date,
      :amount,
      :order_id,
      :status
    ])
    |> validate_required([
      :subscription_id,
      :cycle_number,
      :billing_date,
      :amount,
      :status
    ])
    |> validate_inclusion(:status, @status_options)
    |> validate_number(:cycle_number, greater_than: 0)
    |> validate_number(:amount, greater_than: Decimal.new("0"))
    |> foreign_key_constraint(:subscription_id)
    |> foreign_key_constraint(:order_id)
    |> unique_constraint([:subscription_id, :cycle_number])
  end

  @doc """
  Changeset for updating cycle status.
  """
  def status_changeset(cycle, attrs) do
    cycle
    |> cast(attrs, [:status, :order_id])
    |> validate_required([:status])
    |> validate_inclusion(:status, @status_options)
    |> validate_status_transition()
    |> foreign_key_constraint(:order_id)
  end

  @doc """
  Changeset for completing a cycle with an order.
  """
  def complete_changeset(cycle, attrs) do
    cycle
    |> cast(attrs, [:order_id])
    |> change(status: "completed")
    |> validate_required([:order_id])
    |> validate_inclusion(:status, @status_options)
    |> foreign_key_constraint(:order_id)
  end

  @doc """
  Changeset for marking a cycle as failed.
  """
  def fail_changeset(cycle, _attrs \\ %{}) do
    cycle
    |> change(status: "failed")
    |> validate_inclusion(:status, @status_options)
  end

  # Private Functions

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
  defp valid_status_transition?("pending", new_status) when new_status in ~w(completed failed), do: true
  defp valid_status_transition?("completed", _new_status), do: false
  defp valid_status_transition?("failed", new_status) when new_status in ~w(pending), do: true
  defp valid_status_transition?(_, _), do: false
end
