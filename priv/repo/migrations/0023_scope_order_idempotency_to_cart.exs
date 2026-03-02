defmodule Mercato.Repo.Migrations.ScopeOrderIdempotencyToCart do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add(:source_cart_id, references(:carts, type: :binary_id, on_delete: :nilify_all))
    end

    create(index(:orders, [:source_cart_id]))

    drop_if_exists(index(:orders, [:idempotency_key], name: :orders_idempotency_key_index))

    create(
      unique_index(:orders, [:source_cart_id, :idempotency_key],
        where: "idempotency_key IS NOT NULL",
        name: :orders_source_cart_id_idempotency_key_index
      )
    )
  end
end
