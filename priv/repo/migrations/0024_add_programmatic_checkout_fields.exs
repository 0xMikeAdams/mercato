defmodule Mercato.Repo.Migrations.AddProgrammaticCheckoutFields do
  use Ecto.Migration

  def change do
    alter table(:carts) do
      add :buyer_identity, :map
      add :shipping_address, :map
      add :shipping_method, :string
      add :duties_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
    end

    alter table(:orders) do
      add :duties_total, :decimal, precision: 10, scale: 2, null: false, default: 0.00
    end

    create constraint(:carts, :positive_programmatic_checkout_totals,
      check: "duties_total >= 0"
    )

    create constraint(:orders, :positive_programmatic_checkout_totals,
      check: "duties_total >= 0"
    )
  end
end
