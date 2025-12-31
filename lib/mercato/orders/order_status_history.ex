defmodule Mercato.Orders.OrderStatusHistory do
  @moduledoc """
  Schema for order status change history.

  Maintains an audit trail of all status changes for orders, including
  who made the change, when it occurred, and optional notes.

  ## Fields

  - `order_id`: Reference to the order
  - `from_status`: Previous status (nil for initial status)
  - `to_status`: New status after change
  - `notes`: Optional notes about the status change
  - `changed_by`: Optional reference to user who made the change
  - `changed_at`: Timestamp when the change occurred
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mercato.Orders.Order

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_options ~w(pending processing completed cancelled refunded failed)

  schema "order_status_history" do
    field :from_status, :string
    field :to_status, :string
    field :notes, :string
    field :changed_by, :binary_id
    field :changed_at, :utc_datetime

    belongs_to :order, Order

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new status history entry.
  """
  def changeset(status_history, attrs) do
    status_history
    |> cast(attrs, [
      :order_id,
      :from_status,
      :to_status,
      :notes,
      :changed_by,
      :changed_at
    ])
    |> validate_required([:order_id, :to_status, :changed_at])
    |> validate_inclusion(:from_status, @status_options)
    |> validate_inclusion(:to_status, @status_options)
    |> validate_status_change()
    |> foreign_key_constraint(:order_id)
    |> set_default_changed_at()
  end

  # Private Functions

  defp validate_status_change(changeset) do
    from_status = get_field(changeset, :from_status)
    to_status = get_field(changeset, :to_status)

    if from_status && to_status && from_status == to_status do
      add_error(changeset, :to_status, "cannot be the same as from_status")
    else
      changeset
    end
  end

  defp set_default_changed_at(changeset) do
    case get_field(changeset, :changed_at) do
      nil ->
        put_change(changeset, :changed_at, DateTime.utc_now() |> DateTime.truncate(:second))

      _ ->
        changeset
    end
  end
end
