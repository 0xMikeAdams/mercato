defmodule Mercato.Repo.Migrations.AddIdempotencyKeyToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add(:idempotency_key, :string)
    end

    create(unique_index(:orders, [:idempotency_key], where: "idempotency_key IS NOT NULL"))
  end
end
