defmodule Mercato.Repo.Migrations.CreateOrderStatusHistory do
  use Ecto.Migration

  def change do
    create table(:order_status_history, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :from_status, :string
      add :to_status, :string, null: false
      add :notes, :text
      add :changed_by, :binary_id
      add :changed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:order_status_history, [:order_id])
    create index(:order_status_history, [:changed_at])
    create index(:order_status_history, [:changed_by])
    create index(:order_status_history, [:order_id, :changed_at])

    # Check constraints for valid status values
    create constraint(:order_status_history, :valid_from_status,
      check: "from_status IS NULL OR from_status IN ('pending', 'processing', 'completed', 'cancelled', 'refunded', 'failed')")
    create constraint(:order_status_history, :valid_to_status,
      check: "to_status IN ('pending', 'processing', 'completed', 'cancelled', 'refunded', 'failed')")
  end
end
